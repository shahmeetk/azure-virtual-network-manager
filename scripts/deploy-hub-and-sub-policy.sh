#!/usr/bin/env bash
# Orchestrator: Deploy hub (RG scope) and AVNM policy (Subscription by default; optional MG)
set -euo pipefail

SUB=""
RG=""
LOCATION=""
PARAMS_FILE=""
SPOKES_NG_ID=""
INCLUDE_TAG_NAME="avnm-group"
INCLUDE_TAG_VALUE="spokes"
SCOPE_TYPE="Subscription"            # Subscription (default) or ManagementGroup
MG_ID=""                              # Management Group ID (when SCOPE_TYPE=ManagementGroup)

usage() {
  cat << EOF
Usage: $0 --subscription <SUB_ID> --resource-group <RG> --location <LOCATION> --params <HUB_PARAMS_JSON> [--include-tag-name <NAME>] [--include-tag-value <VALUE>] [--scope-type <Subscription|ManagementGroup>] [--management-group-id <MG_ID>]

Steps:
  1) az deployment group create (hub/main.bicep)
  2) Extract spokesNetworkGroupId from outputs
  3) Deploy unified AVNM Policy (modules/avnm-policy.bicep):
     - Default: Subscription scope
     - Optional: Management Group scope when --scope-type ManagementGroup and --management-group-id provided

Examples:
  $0 --subscription 000... --resource-group aznm-test --location eastus --params 1-platform-deployment/hub/main.parameters.json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="$2"; shift 2;;
    --resource-group) RG="$2"; shift 2;;
    --location) LOCATION="$2"; shift 2;;
    --params) PARAMS_FILE="$2"; shift 2;;
    --include-tag-name) INCLUDE_TAG_NAME="$2"; shift 2;;
    --include-tag-value) INCLUDE_TAG_VALUE="$2"; shift 2;;
    --scope-type) SCOPE_TYPE="$2"; shift 2;;
    --management-group-id) MG_ID="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$SUB" || -z "$RG" || -z "$LOCATION" || -z "$PARAMS_FILE" ]]; then
  echo "Missing required arguments." >&2; usage; exit 1
fi

# Optionally hydrate script variables from the parameters file so a single JSON drives both steps
if command -v jq >/dev/null 2>&1; then
  # Tag parameters (only override defaults if present in file)
  FILE_TAG_NAME=$(jq -r '.parameters.includeTagName.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  FILE_TAG_VALUE=$(jq -r '.parameters.includeTagValue.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  if [[ -n "$FILE_TAG_NAME" ]]; then INCLUDE_TAG_NAME="$FILE_TAG_NAME"; fi
  if [[ -n "$FILE_TAG_VALUE" ]]; then INCLUDE_TAG_VALUE="$FILE_TAG_VALUE"; fi

  # Scope parameters
  FILE_SCOPE_TYPE=$(jq -r '.parameters.policyScopeType.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  FILE_SCOPE_SUB=$(jq -r '.parameters.policySubscriptionId.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  FILE_SCOPE_MG=$(jq -r '.parameters.policyManagementGroupId.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  if [[ -n "$FILE_SCOPE_TYPE" ]]; then SCOPE_TYPE="$FILE_SCOPE_TYPE"; fi
  if [[ -z "$MG_ID" && -n "$FILE_SCOPE_MG" ]]; then MG_ID="$FILE_SCOPE_MG"; fi
  if [[ "$SCOPE_TYPE" == "Subscription" && -n "$FILE_SCOPE_SUB" ]]; then SUB="$FILE_SCOPE_SUB"; fi
fi

az account set --subscription "$SUB"

DEP=main-$(date +%Y%m%d-%H%M%S)

echo "[1/3] Deploying hub (RG scope) ..."
az deployment group create \
  --resource-group "$RG" \
  --name "$DEP" \
  --template-file azure-enterprise-bicep/1-platform-deployment/hub/main.bicep \
  --parameters @"$PARAMS_FILE" \
  --verbose

echo "[2/3] Extracting spokesNetworkGroupId from outputs ..."
SPOKES_NG_ID=$(az deployment group show -g "$RG" -n "$DEP" --query "properties.outputs.spokesNetworkGroupId.value" -o tsv)
if [[ -z "$SPOKES_NG_ID" ]]; then
  echo "Could not extract spokesNetworkGroupId from deployment outputs." >&2
  exit 1
fi

echo "[3/3] Deploying AVNM policy (${SCOPE_TYPE}) ..."

if [[ "$SCOPE_TYPE" == "ManagementGroup" ]]; then
  if [[ -z "$MG_ID" ]]; then
    echo "--scope-type ManagementGroup requires --management-group-id <MG_ID>" >&2
    exit 1
  fi
  az deployment mg create \
    --name avnm-mg-policy-$(date +%Y%m%d-%H%M%S) \
    --location "$LOCATION" \
    --management-group-id "$MG_ID" \
    --template-file azure-enterprise-bicep/1-platform-deployment/hub/modules/mg-avnm-policy.bicep \
    --parameters parentManagementGroupId="$MG_ID" spokesNetworkGroupId="$SPOKES_NG_ID" includeTagName="$INCLUDE_TAG_NAME" includeTagValue="$INCLUDE_TAG_VALUE" \
    --verbose
else
  az deployment sub create \
    --name avnm-sub-policy-$(date +%Y%m%d-%H%M%S) \
    --location "$LOCATION" \
    --template-file azure-enterprise-bicep/1-platform-deployment/hub/modules/avnm-policy.bicep \
    --parameters spokesNetworkGroupId="$SPOKES_NG_ID" includeTagName="$INCLUDE_TAG_NAME" includeTagValue="$INCLUDE_TAG_VALUE" \
    --verbose
fi

echo "Done."
