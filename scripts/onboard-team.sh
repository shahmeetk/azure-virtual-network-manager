#!/usr/bin/env bash
# Orchestrator: Team Onboarding (Dual mode)
# - managementGroup: Create Team MG + subscriptions, then Spoke VNets from IPAM
# - subscription   : Create RGs + Spoke VNets in current subscription from IPAM
# - Reads parameters from infrastructure/spoke-team-onboarding/*.parameters.json (or a custom file)
# - Mirrors style and UX of deploy-hub-and-sub-policy.sh

set -euo pipefail

SUB=""                  # Azure subscription for az context
LOCATION=""             # Deployment location for subscription deployment record
PARAMS_FILE=""          # Path to team onboarding parameters JSON
DEPLOYMENT_NAME="team-onboard-$(date +%Y%m%d-%H%M%S)"
WHAT_IF=false

usage() {
  cat << EOF
Usage: $0 --subscription <SUB_ID> --location <LOCATION> --params <TEAM_PARAMS_JSON> [--what-if] [--name <DEPLOYMENT_NAME>]

Description:
  Onboards a team within the current subscription by creating (or reusing) a spoke
  Resource Group and deploying a spoke VNet carved from the AVNM IPAM pool.

Required:
  --subscription        Subscription to set az context
  --location            Azure region to store the deployment record (e.g., eastus)
  --params              Path to JSON parameters file (e.g., infrastructure/spoke-team-onboarding/main.parameters.json)

Optional:
  --what-if             Run what-if instead of an actual deployment
  --name                Custom deployment name (default: team-onboard-YYYYMMDD-HHMMSS)

Examples:
  $0 --subscription 00000000-0000-0000-0000-000000000000 \\
     --location eastus \\
     --params infrastructure/spoke-team-onboarding/main.parameters.json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="$2"; shift 2;;
    --location) LOCATION="$2"; shift 2;;
    --params) PARAMS_FILE="$2"; shift 2;;
    --what-if) WHAT_IF=true; shift 1;;
    --name) DEPLOYMENT_NAME="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$SUB" || -z "$LOCATION" || -z "$PARAMS_FILE" ]]; then
  echo "Missing required arguments." >&2; usage; exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Please install jq to use this script." >&2
  exit 1
fi

if [[ ! -f "$PARAMS_FILE" ]]; then
  echo "Error: parameters file '$PARAMS_FILE' not found." >&2; exit 1
fi

# Resolve template paths relative to the parameters file directory
PARAM_DIR=$(cd "$(dirname "$PARAMS_FILE")" && pwd)

# Optional: read subscriptionId from params if --subscription not provided
if [[ -z "$SUB" ]]; then
  SUB_FROM_FILE=$(jq -r '.parameters.subscriptionId.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  if [[ -n "$SUB_FROM_FILE" ]]; then SUB="$SUB_FROM_FILE"; fi
fi

REQUIRED_KEYS=(location environment spokeResourceGroupName)
for key in "${REQUIRED_KEYS[@]}"; do
  val=$(jq -r --arg k "$key" '.parameters[$k].value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  if [[ -z "$val" ]]; then
    echo "Parameter '$key' is missing or empty in $PARAMS_FILE" >&2
  fi
done

az account set --subscription "$SUB"

echo "[Team Onboarding] Starting subscription-scope deployment (${DEPLOYMENT_NAME})..."

# Build safe parameter list excluding helper-only keys (e.g., subscriptionId)
ENVIRONMENT=$(jq -r '.parameters.environment.value' "$PARAMS_FILE")
SPOKE_RG=$(jq -r '.parameters.spokeResourceGroupName.value' "$PARAMS_FILE")
IPAM_POOL_ID=$(jq -r '.parameters.ipamPoolId.value // empty' "$PARAMS_FILE")
VNET_BITS=$(jq -r '.parameters.vnetSizeInBits.value // 24' "$PARAMS_FILE")
RESOURCE_TAGS=$(jq -c '.parameters.resourceTags.value // {}' "$PARAMS_FILE")
VNET_PREFIXES=$(jq -c '.parameters.virtualNetworkAddressPrefixes.value // []' "$PARAMS_FILE")

echo "[Team Onboarding] Resolved parameters:"
echo "  Environment: ${ENVIRONMENT}"
echo "  Spoke Resource Group: ${SPOKE_RG}"
echo "  IPAM Pool Id: ${IPAM_POOL_ID:+<provided>}"
echo "  VNet Size (bits): ${VNET_BITS}"

if [[ -z "$IPAM_POOL_ID" ]]; then
  echo "Error: ipamPoolId is required and must be provided in params." >&2
  exit 1
fi

PARAMS_ARGS=(
  "location=$LOCATION"
  "environment=$ENVIRONMENT"
  "ipamPoolId=$IPAM_POOL_ID"
  "spokeResourceGroupName=$SPOKE_RG"
  "vnetSizeInBits=$VNET_BITS"
  "resourceTags=$RESOURCE_TAGS"
  "virtualNetworkAddressPrefixes=$VNET_PREFIXES"
)

if [[ "$WHAT_IF" == true ]]; then
  az deployment sub what-if \
    --name "$DEPLOYMENT_NAME" \
    --location "$LOCATION" \
    --template-file "$PARAM_DIR/subscription-main.bicep" \
    --parameters "${PARAMS_ARGS[@]}" \
    --verbose
  echo "What-if completed. No changes were applied."
  exit 0
fi

az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$PARAM_DIR/subscription-main.bicep" \
  --parameters "${PARAMS_ARGS[@]}" \
  --verbose
echo "[Team Onboarding] Deployment complete. Resources were created in current subscription."
echo "Done."
