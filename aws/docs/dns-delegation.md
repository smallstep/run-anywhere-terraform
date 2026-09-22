# DNS delegation

Terraform creates the public zone for `base_domain` in `platform`
(`modules/dns`); the parent zone is managed elsewhere and must delegate to it
once, by hand. Until that NS record exists nothing under the domain resolves
publicly — and two later steps fail in ways that look unrelated to DNS.

## Why this must happen before workloads-apply and kots-install

Public resolution of the zone is load-bearing three times over:

- **The CRL certificate.** In the default `crl_mode = cloudfront`, `platform`
  itself blocks on ACM validating the `crl.<base_domain>` certificate through
  DNS, and times out if the zone is not delegated.
- **Let's Encrypt HTTP-01.** The platform's default TLS issuer validates by
  fetching a challenge over plain HTTP at the application's public hostnames.
  If `app.<base_domain>` does not resolve on the public internet, no
  certificate is ever issued and every platform hostname serves a broken
  chain indefinitely — the application looks "up but wrong" rather than down.
- **KOTS preflights.** `make kots-install` runs the application's preflight
  checks, which resolve the configured hostnames before deploying.
  Undelegated DNS fails preflights or, worse, passes against a stale cache
  and produces the Let's Encrypt failure above.

The sequence from `workloads-apply` onward runs without a natural pause, so
the delegation gate sits between `platform-apply` and everything after it.
Do it once, confirm it, forget it.

## The steps

**1. Read the name servers Terraform assigned.** The zone must exist first,
so this comes after `make platform-apply`:

```bash
terraform -chdir=platform output route53_name_servers
```

Four names, `awsdns-*` hosts.

**2. Create the NS record in the parent.** Wherever the parent zone is
managed, add:

```
<base_domain>.   NS   <the four name servers from step 1>
```

TTL is your choice; 300 is kind to you if the zone is ever recreated.

**3. Confirm delegation before spending half an hour finding out.**

```bash
# The delegation itself, from a public resolver:
dig +short NS <base_domain> @8.8.8.8

# A record inside the zone, proving the delegated servers answer. There is
# no zone-apex record; platform hostnames are A records pointing at the
# lobby EIPs:
dig +short A app.<base_domain> @8.8.8.8

# Optional: the *.ca wildcard, the same probe name `verify STAGE=dns` uses:
dig +short A probe.ca.<base_domain> @8.8.8.8
```

When the NS and `app` queries answer, proceed. `make verify STAGE=dns`
performs the same checks scripted. Propagation is usually under a minute for
a fresh delegation. If you queried before delegating, the parent's NXDOMAIN
answer may be cached for up to its negative TTL.

## Tearing down

`make platform-destroy` removes the zone. The NS record in the parent then
points at name servers that no longer host anything — harmless but untidy;
remove it too. Re-creating the zone later assigns a **different** set of name
servers and needs a fresh delegation: the four values are not stable across
zone lifetimes.
