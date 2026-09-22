#!/bin/bash
# shellcheck disable=SC2034  # this file exists to define variables for sourcers
# Shared helpers for every script in aws/scripts. Source, don't execute:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Provides: info/warn/die, conf (install.conf reader), tf_out (terraform output
# reader), require (tool presence), need_env (variable presence), and the
# deployment-identity variables below. Sources .env when present so the API
# token reaches the scripts without living in the environment permanently.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LIB_DIR}/.." && pwd)"
CONF="${REPO_ROOT}/install.conf"
BUILD_DIR="${REPO_ROOT}/build"

info() { echo "[$(date +%H:%M:%S)] $*"; }
warn() { echo "[$(date +%H:%M:%S)] WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -f "$CONF" ] || die "install.conf not found at ${CONF} — copy install.conf.example"

# conf NAME [DEFAULT] — read a simple `name = "value"` assignment from install.conf.
conf() {
  local v
  v="$(sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\\1/p" "$CONF" | head -1)"
  echo "${v:-${2:-}}"
}

# The same values the platform root was applied with. generate-config-values.sh
# refuses to render when the Terraform outputs disagree with these, which is
# the guard against pointing this tooling at the wrong state.
NAME="$(conf name smallstep)"
REGION="$(conf region us-east-2)"
BASE_DOMAIN="$(conf base_domain)"
NAMESPACE="$(conf namespace smallstep)"
TEAM_NAME="$(conf team_name)"
TEAM_SLUG="$(conf team_slug)"

# The channel slug is what `kubectl kots install smallstep/<slug>` names; a
# license restricted to a channel is refused by any other slug. Replicated
# shows it next to the channel in the vendor portal; it is the lowercased
# channel name unless that name has been used before.
REPLICATED_CHANNEL_SLUG="$(conf replicated_channel_slug)"

# The license file is downloaded from the Replicated vendor portal (or handed
# over by Smallstep). It lives outside the repo so a `git clean` can never eat
# it and a stray `git add` can never leak it.
: "${LICENSE_FILE:=${HOME}/.local/share/${NAME}/license.yaml}"
export LICENSE_FILE

# kubectl and the kots CLI read whatever context ~/.kube/config last used,
# which on an operator machine with several clusters is anyone's guess. This
# deployment owns its own kubeconfig instead: `make kubeconfig` writes it once
# the cluster exists, and every script and make target inherits it through
# this export. Nothing sourcing this file can reach any other cluster.
: "${KUBECONFIG:=${HOME}/.local/share/${NAME}/kubeconfig}"
export KUBECONFIG

# .env carries the dashboard API token, which `verify.sh app` asserts with
# need_env (see env.example).
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

require() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null || die "required tool not installed: $t"
  done
}

need_env() {
  local v
  for v in "$@"; do
    [ -n "${!v:-}" ] || die "required variable $v is empty — see env.example"
  done
}

# need_kubeconfig — refuse to touch a cluster until the deployment-owned
# kubeconfig exists. The alternative failure mode is kubectl silently using the
# operator's current context, which is the one thing these scripts must never
# do.
need_kubeconfig() {
  [ -s "$KUBECONFIG" ] \
    || die "no kubeconfig at ${KUBECONFIG} — run: make kubeconfig (after make platform-apply)"
}

# tf_out ROOT NAME — read one output from a Terraform root (platform or
# workloads). -raw for strings; callers needing lists/maps use tf_out_json.
tf_out() {
  terraform -chdir="${REPO_ROOT}/$1" output -raw "$2"
}

tf_out_json() {
  terraform -chdir="${REPO_ROOT}/$1" output -json "$2"
}

mkdir -p "$BUILD_DIR"
