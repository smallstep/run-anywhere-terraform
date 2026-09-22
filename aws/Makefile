# Smallstep Run Anywhere on AWS: every workflow, in install order. Run from
# this directory (`make help`) or with `make -C aws ...`.
#
# Two Terraform roots, each with its own state, each independently applyable:
# platform builds AWS infrastructure; workloads deploys cluster addons and the
# bootstrap Job onto it. The KOTS install itself is deliberately a script, not
# Terraform — see scripts/kots-install.sh.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# `name` from install.conf names the per-deployment state directory, the same
# way scripts/lib.sh derives it.
NAME := $(shell sed -n -E 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' install.conf 2>/dev/null | head -1)
NAME := $(if $(NAME),$(NAME),smallstep)

# The Replicated license lives outside the repo (never in git). Download it
# from the vendor portal and place it here.
LICENSE_FILE ?= $(HOME)/.local/share/$(NAME)/license.yaml
export LICENSE_FILE

# kubectl and kots follow whatever context ~/.kube/config last used. This
# deployment owns its own kubeconfig instead (make kubeconfig); scripts/lib.sh
# exports the same default, so scripts and targets can never reach a cluster
# that is not this deployment's.
KUBECONFIG ?= $(HOME)/.local/share/$(NAME)/kubeconfig
export KUBECONFIG

PLATFORM  := platform
WORKLOADS := workloads
TF_ROOTS  := $(PLATFORM) $(WORKLOADS)

# Minimum Terraform. 1.11 gates S3-native locking (use_lockfile), write-only
# arguments, and ephemeral resources — all three are load-bearing here.
TF_MIN := 1.11.0

STAGE ?= platform

.PHONY: help preflight fmt validate check \
        platform-init platform-plan platform-apply platform-destroy \
        workloads-init workloads-plan workloads-apply workloads-destroy \
        state-bucket kubeconfig config-values kots-install kots-status kots-console \
        dns-reconcile verify destroy-all

help:
	@echo "Smallstep Run Anywhere on AWS"
	@echo
	@echo "  make preflight        verify tooling, AWS identity, and the license file"
	@echo "  make fmt              terraform fmt -recursive"
	@echo "  make validate         validate every Terraform root (no credentials needed)"
	@echo "  make check            fmt + validate"
	@echo
	@echo "Install path (order matters):"
	@echo
	@echo "  make state-bucket     one-time state bucket + backend.hcl for each root"
	@echo "  make platform-{init,plan,apply,destroy}    AWS infrastructure (~25 min)"
	@echo "  # delegate NS records for base_domain to the Route 53 zone, then:"
	@echo "  make kubeconfig       write the deployment-owned kubeconfig"
	@echo "  make workloads-{init,plan,apply,destroy}   addons + bootstrap Job"
	@echo "  make config-values    render KOTS ConfigValues from terraform outputs"
	@echo "  make kots-install     headless install from your channel (20-30 min)"
	@echo "  make dns-reconcile    point control.infra at the mission-control NLB"
	@echo "  make verify STAGE=x   platform | dns | cluster | app"
	@echo
	@echo "  make kots-status      app + workload status at a glance"
	@echo "  make kots-console     port-forward the KOTS admin console to :8800"
	@echo "  make destroy-all      remove workloads and platform (state bucket survives)"

preflight:
	@fail=0; \
	printf '%-22s' "terraform"; \
	if command -v terraform >/dev/null; then \
	  v=$$(terraform version -json 2>/dev/null | grep -oP '"terraform_version":\s*"\K[^"]+' || terraform version | head -1 | tr -d 'Terraform v'); \
	  if [ "$$(printf '%s\n%s\n' "$(TF_MIN)" "$$v" | sort -V | head -1)" = "$(TF_MIN)" ]; then \
	    echo "ok ($$v)"; else echo "TOO OLD ($$v, need >= $(TF_MIN))"; fail=1; fi; \
	else echo "MISSING"; fail=1; fi; \
	for t in aws kubectl helm jq curl dig; do \
	  printf '%-22s' "$$t"; \
	  if command -v $$t >/dev/null; then echo "ok"; else echo "MISSING"; fail=1; fi; \
	done; \
	printf '%-22s' "kubectl-kots"; \
	if kubectl kots version >/dev/null 2>&1; then echo "ok ($$(kubectl kots version 2>/dev/null | head -1))"; \
	else echo "MISSING — curl https://kots.io/install | bash"; fail=1; fi; \
	printf '%-22s' "install.conf"; \
	if [ -s install.conf ]; then echo "ok"; else echo "MISSING — cp install.conf.example install.conf"; fail=1; fi; \
	printf '%-22s' "license file"; \
	if [ -s "$(LICENSE_FILE)" ]; then \
	  ch=$$(grep -m1 -E '^\s*channelName:' "$(LICENSE_FILE)" | awk '{print $$2}'); \
	  cust=$$(grep -m1 -E '^\s*customerName:' "$(LICENSE_FILE)" | sed 's/^\s*customerName:\s*//'); \
	  echo "ok ($$cust, channel $$ch)"; \
	else echo "MISSING at $(LICENSE_FILE) — download it from the Replicated vendor portal"; fail=1; fi; \
	printf '%-22s' "kube context"; \
	if [ -s "$(KUBECONFIG)" ]; then \
	  ctx=$$(kubectl config current-context 2>/dev/null); \
	  want=$$(sed -n -E 's/^[[:space:]]*account_id[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' install.conf | head -1); \
	  case "$$ctx" in *:$$want:cluster/*) echo "ok ($$ctx)";; \
	    *) echo "WRONG CLUSTER ($$ctx) — run: make kubeconfig"; fail=1;; esac; \
	else echo "not yet ($(KUBECONFIG)) — run: make kubeconfig after platform-apply"; fi; \
	printf '%-22s' "aws identity"; \
	acct=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null); \
	want=$$(sed -n -E 's/^[[:space:]]*account_id[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' install.conf | head -1); \
	if [ -z "$$acct" ]; then echo "NOT AUTHENTICATED"; fail=1; \
	elif [ -z "$$want" ]; then echo "UNPINNED ($$acct) — set account_id in install.conf"; fail=1; \
	elif [ "$$acct" != "$$want" ]; then echo "WRONG ACCOUNT ($$acct, expected $$want)"; fail=1; \
	else echo "ok ($$acct)"; fi; \
	echo; \
	if [ $$fail -ne 0 ]; then echo "preflight FAILED"; exit 1; else echo "preflight passed"; fi

fmt:
	terraform fmt -recursive .

# Credential-free, which is the promise in `make help`. The init is skipped
# when .terraform already exists: `init -backend=false` on a root that has
# been initialised against S3 still touches the backend, so it fails on
# expired credentials and breaks that promise.
validate:
	@for d in $(TF_ROOTS); do \
	  echo "==> $$d"; \
	  if [ ! -d "$$d/.terraform" ]; then \
	    terraform -chdir=$$d init -backend=false -input=false >/dev/null || exit 1; \
	  fi; \
	  terraform -chdir=$$d validate || exit 1; \
	done

check: fmt validate

# tf_targets <prefix> <dir> — the four verbs for one Terraform root.
define tf_targets
$(1)-init:
	terraform -chdir=$(2) init -backend-config=backend.hcl
$(1)-plan:
	terraform -chdir=$(2) plan
$(1)-apply:
	terraform -chdir=$(2) apply
$(1)-destroy:
	terraform -chdir=$(2) destroy
endef

$(eval $(call tf_targets,platform,$(PLATFORM)))
$(eval $(call tf_targets,workloads,$(WORKLOADS)))

state-bucket:
	scripts/bootstrap-state-bucket.sh

kubeconfig:
	scripts/kubeconfig.sh

config-values:
	scripts/generate-config-values.sh

kots-install:
	scripts/kots-install.sh

kots-status:
	@kubectl kots get apps -n $$(sed -n -E 's/^[[:space:]]*namespace[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' install.conf | head -1) || true
	@kubectl -n $$(sed -n -E 's/^[[:space:]]*namespace[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' install.conf | head -1) get deploy,sts 2>/dev/null | head -40

kots-console:
	kubectl kots admin-console -n $$(sed -n -E 's/^[[:space:]]*namespace[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' install.conf | head -1)

dns-reconcile:
	scripts/reconcile-dns.sh

verify:
	scripts/verify.sh $(STAGE)

destroy-all:
	@echo "This destroys the workloads and the platform (the state bucket survives)."
	@echo "NOTE: the platform creates CA keys in KMS at runtime; Terraform does not know"
	@echo "about them. After destroy, schedule their deletion in KMS by hand."
	@read -p "Type the deployment name to confirm: " c; \
	  want=$$(sed -n -E 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' install.conf | head -1); \
	  [ "$$c" = "$$want" ] || { echo "aborted"; exit 1; }
	-$(MAKE) workloads-destroy
	$(MAKE) platform-destroy
	@echo "Done. The state bucket is intentionally left behind."
