#!/usr/bin/env bash
# DEPRECATED — This helper is no longer used. Connectivity is provisioned natively
# via modules/avnm-configs.bicep (api-version 2024-10-01). This script is kept
# temporarily for backward compatibility and will be removed.
#
# If you reached this script, please switch to deploying:
#   azure-enterprise-bicep/1-platform-deployment/hub/main.bicep
# and set parameter deployConnectivity=true when ready.

echo "[DEPRECATED] scripts/connectivity-autoprobe.sh is deprecated. Use the Bicep module instead (modules/avnm-configs.bicep)."
exit 0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  cat << EOF
Usage: $0 --subscription <SUB_ID> --resource-group <RG> --avnm-name <NAME> --hub-vnet-id <VNET_ID> [--spokes-ng-id <NG_ID>]

Description:
  Attempts to create AVNM connectivity configuration 'cc-hub-and-spoke' under the specified AVNM by trying
  multiple api-versions and payload variants. Stops at the first success. If all variants fail,
  prints a compact failure summary with the last error message.

Required:
  --subscription       Subscription ID
  --resource-group     Resource Group name
  --avnm-name          AVNM resource name (e.g., test-avnm)
  --hub-vnet-id        Full resource ID of the hub VNet

Optional:
  --spokes-ng-id       Resource ID of the spokes Network Group. If provided, one payload variant will include appliesToGroups.

Examples:
  $0 --subscription 00000000-0000-0000-0000-000000000000 \
     --resource-group aznm-test \
     --avnm-name test-avnm \
     --hub-vnet-id /subscriptions/.../resourceGroups/aznm-test/providers/Microsoft.Network/virtualNetworks/aznm-test-vnet

EOF
}

SUB=""
RG=""
AVNM=""
HUB_VNET_ID=""
SPOKES_NG_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="$2"; shift 2;;
    --resource-group) RG="$2"; shift 2;;
    --avnm-name) AVNM="$2"; shift 2;;
    --hub-vnet-id) HUB_VNET_ID="$2"; shift 2;;
    --spokes-ng-id) SPOKES_NG_ID="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo -e "${RED}Unknown option:${NC} $1"; usage; exit 1;;
  esac
done

if [[ -z "$SUB" || -z "$RG" || -z "$AVNM" || -z "$HUB_VNET_ID" ]]; then
  echo -e "${RED}Missing required arguments.${NC}"; usage; exit 1
fi

CONFIG_NAME="cc-hub-and-spoke"
BASE_URI="/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Network/networkManagers/${AVNM}/connectivityConfigurations/${CONFIG_NAME}"

APIS=(
  "2024-05-01"
  "2024-07-01"
  "2024-10-01"
)

# Payload variants — minimal first, then add properties incrementally
build_payload() {
  local variant="$1"
  case "$variant" in
    1)
      cat <<JSON
{ "properties": {
    "connectivityTopology": "HubAndSpoke",
    "hubs": [ { "resourceId": "${HUB_VNET_ID}" } ]
} }
JSON
      ;;
    2)
      cat <<JSON
{ "properties": {
    "connectivityTopology": "HubAndSpoke",
    "groupConnectivity": "None",
    "hubs": [ { "resourceId": "${HUB_VNET_ID}" } ]
} }
JSON
      ;;
    3)
      if [[ -z "$SPOKES_NG_ID" ]]; then
        return 1
      fi
      cat <<JSON
{ "properties": {
    "connectivityTopology": "HubAndSpoke",
    "groupConnectivity": "None",
    "hubs": [ { "resourceId": "${HUB_VNET_ID}" } ],
    "appliesToGroups": [ { "networkGroupId": "${SPOKES_NG_ID}" } ]
} }
JSON
      ;;
    *) return 1;;
  esac
}

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

ensure_login() {
  if ! az account show >/dev/null 2>&1; then
    err "Not logged into Azure. Run 'az login' first."; exit 1
  fi
  az account set --subscription "$SUB" >/dev/null
}

probe() {
  local api="$1"; local variant="$2"
  local uri="${BASE_URI}?api-version=${api}"
  local body
  if ! body=$(build_payload "$variant"); then
    return 2
  fi
  log "Trying api-version ${api}, variant ${variant}..."
  set +e
  local out
  out=$(az rest --method put --uri "$uri" --body "$body" 2>&1)
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    ok "Succeeded with api=${api}, variant=${variant}"
    echo "$out" | sed -e 's/^/  /'
    return 0
  else
    warn "Failed (api=${api}, variant=${variant})"; echo "$out" | sed -e 's/^/    /'
    return 1
  fi
}

main() {
  ensure_login
  local last_err=1
  for api in "${APIS[@]}"; do
    for variant in 1 2 3; do
      if probe "$api" "$variant"; then
        ok "Connectivity configuration created (api=${api}, variant=${variant})."
        exit 0
      fi
    done
  done
  err "All connectivity probe attempts failed. See logs above."
  exit 1
}

main "$@"
