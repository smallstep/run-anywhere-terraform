# Egress requirements

What the platform talks to on the internet. The footprint is
install-time-heavy and runtime-light, and there is no runtime phone-home.

## Install and upgrade time

Three Replicated endpoints, all on :443, only during `make kots-install` and
subsequent upgrades:

| Endpoint | Purpose |
|----------|---------|
| `replicated.app` | License validation, application release metadata |
| `registry.replicated.com` | The application's container images |
| `proxy.replicated.com` | Proxied upstream images (pull-through) |

Nothing in the running platform calls these. A cluster that never upgrades
again could have all three blocked the day after install and would not
notice. The allow-list for steady-state operation contains none of the
vendor's infrastructure.

## Runtime

| Destination | When | Notes |
|-------------|------|-------|
| Let's Encrypt (`acme-v02.api.letsencrypt.org`, :443) | Certificate issuance and renewal for the platform's own TLS | Removable: configure a private issuer instead and this egress disappears. |
| SMTP relay | Invitation and notification email | SES in-region with the default `smtp_mode = ses` (`modules/ses-smtp`), or whatever relay you already operate. |
| MDM APIs (Jamf, Intune / Microsoft Graph, …) | Only when device inventory sync is configured | Outbound-only polling from the platform to the MDM vendor's published API hostnames; nothing inbound is required. |
| Identity provider | OIDC login | SSO redirects happen in the user's browser; the platform itself fetches the IdP's OIDC discovery document and JWKS. SCIM provisioning is the IdP calling *in* to the platform, not egress. |
| AWS service endpoints (KMS, S3, Secrets Manager, RDS, ElastiCache, CloudWatch) | Always | Reached in-region; S3 through the gateway endpoint when the module creates the VPC. |

Device agents and SSH clients talk to the platform's own hostnames
(`*.<base_domain>`); that traffic is inbound to the platform, not egress
from it.

## The mirrored-registry path

KOTS supports installing from a private OCI registry: images are pushed to
your registry and the install is pointed at it (`kubectl kots install
--kotsadm-registry <registry>` plus registry credentials; the application's
image references are rewritten at deploy time). Any OCI-compliant registry
works. In that configuration the cluster nodes pull only from the internal
registry, and the Replicated endpoints are reached once, from wherever the
images are staged — which can be a connected workstation rather than the
cluster.

Fully air-gapped installs — the `.airgap` bundle KOTS can install with zero
connectivity — are not currently supported for this application. The
mirrored-registry path still requires a connected staging step for each
release.
