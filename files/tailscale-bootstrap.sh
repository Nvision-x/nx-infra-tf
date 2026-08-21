#!/usr/bin/env bash
# Registers this host on the tailnet as a tagged exit node / subnet router.
# Safe to re-run: exits early once the node is logged in.
#
# Config comes from /etc/nx-tailscale.env (written by user-data) or the
# environment. On hosts with no AWS access (customer on-prem) export TS_AUTHKEY
# and the TS_* settings directly before running.
set -euo pipefail

if [[ -f /etc/nx-tailscale.env ]]; then
  # shellcheck disable=SC1091
  . /etc/nx-tailscale.env
fi

TS_AUTHKEY_PARAM="${TS_AUTHKEY_PARAM:-/nx/tailscale/bastion-authkey}"
TS_TAGS="${TS_TAGS:-tag:exit-node}"
TS_ROUTES="${TS_ROUTES:-}"
TS_HOSTNAME="${TS_HOSTNAME:-}"
TS_ACCEPT_ROUTES="${TS_ACCEPT_ROUTES:-true}"
# TS_FORCE=true re-auths a node that is already up, which is how a user-owned
# node gets moved onto a tag
TS_FORCE="${TS_FORCE:-false}"

log() { echo "[tailscale-bootstrap] $*"; }

if [[ "$TS_FORCE" != "true" ]] &&
  tailscale status --json 2>/dev/null | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
  log "already registered, nothing to do"
  exit 0
fi

if [[ -z "${TS_AUTHKEY:-}" ]]; then
  if [[ -z "${AWS_REGION:-}${AWS_DEFAULT_REGION:-}" ]]; then
    imds_token=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 300" || true)
    AWS_DEFAULT_REGION=$(curl -fsS -H "X-aws-ec2-metadata-token: $imds_token" \
      http://169.254.169.254/latest/meta-data/placement/region || true)
    export AWS_DEFAULT_REGION
  fi
  log "reading auth key from SSM $TS_AUTHKEY_PARAM"
  TS_AUTHKEY=$(aws ssm get-parameter --name "$TS_AUTHKEY_PARAM" --with-decryption \
    --query Parameter.Value --output text)
fi

if [[ -z "$TS_AUTHKEY" || "$TS_AUTHKEY" == "PLACEHOLDER" ]]; then
  log "no auth key in $TS_AUTHKEY_PARAM - paste the tagged key and re-run"
  exit 1
fi

# --accept-dns=false always: if tailscale manages resolv.conf on the box that IS
# the VPN, a bad tailnet DNS config takes out the box's own resolution (and the
# SSM agent with it)
args=(--authkey="$TS_AUTHKEY" --advertise-tags="$TS_TAGS" --advertise-exit-node --accept-dns=false)
if [[ -n "$TS_ROUTES" ]]; then
  args+=(--advertise-routes="$TS_ROUTES")
fi
if [[ -n "$TS_HOSTNAME" ]]; then
  args+=(--hostname="$TS_HOSTNAME")
fi
if [[ "$TS_ACCEPT_ROUTES" == "true" ]]; then
  args+=(--accept-routes)
fi
if [[ "$TS_FORCE" == "true" ]]; then
  args+=(--force-reauth)
fi

log "registering ${TS_HOSTNAME:-$(hostname)} tags=$TS_TAGS routes=${TS_ROUTES:-none}"
tailscale up "${args[@]}"
tailscale status --self --peers=false || true
