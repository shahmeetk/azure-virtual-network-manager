#!/usr/bin/env bash
# Orchestrator: Deploy hub (RG scope) and AVNM policy (Subscription by default; optional MG)
set -euo pipefail

# --- Defaults ---
SUB=""
RG=""
LOCATION=""
PARAMS_FILE=""
SCOPE_TYPE="Subscription"
MG_ID=""

# --- Functions ---
usage() {
  cat << EOF
Usage: $0 --subscription <SUB_ID> --resource-group <RG> --location <LOCATION> --params <HUB_PARAMS_JSON> [--scope-type <Subscription|ManagementGroup>] [--management-group-id <MG_ID>]

Description:
  This script orchestrates the deployment of the AVNM hub and its associated policy.
  It first deploys the Bicep template for the hub resources to a resource group.
  Then, it extracts the ID of the dynamically created 'spokes' network group.
  Finally, it deploys a policy at either the subscription or management group scope
  to automatically add VNets with a specific tag to that network group.

Arguments:
  --subscription <SUB_ID>         (Required) The subscription ID for the deployment.
  --resource-group <RG>           (Required) The resource group for the hub deployment.
  --location <LOCATION>           (Required) The Azure region for the deployment.
  --params <HUB_PARAMS_JSON>      (Required) Path to the parameters file for the hub deployment.
  --scope-type <TYPE>             (Optional) The scope for the policy assignment. Can be 'Subscription' or 'ManagementGroup'. Defaults to 'Subscription'.
  --management-group-id <MG_ID>   (Optional) The management group ID, required if --scope-type is 'ManagementGroup'.
  -h, --help                      Show this help message.
EOF
}

# --- Argument Parsing & Validation ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --subscription" >&2; usage; exit 1; fi
      SUB="$2"; shift 2;;
    --resource-group)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --resource-group" >&2; usage; exit 1; fi
      RG="$2"; shift 2;;
    --location)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --location" >&2; usage; exit 1; fi
      LOCATION="$2"; shift 2;;
    --params)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --params" >&2; usage; exit 1; fi
      PARAMS_FILE="$2"; shift 2;;
    --scope-type)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --scope-type" >&2; usage; exit 1; fi
      SCOPE_TYPE="$2"; shift 2;;
    --management-group-id)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --management-group-id" >&2; usage; exit 1; fi
      MG_ID="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# --- Final Validation ---
if [[ -z "$SUB" || -z "$RG" || -z "$LOCATION" || -z "$PARAMS_FILE" ]]; then
  echo "Error: Missing one or more required arguments." >&2
  usage
  exit 1
fi

if [[ ! -f "$PARAMS_FILE" ]]; then
  echo "Error: Parameters file not found at '$PARAMS_FILE'" >&2
  exit 1
fi

if [[ "$SCOPE_TYPE" == "ManagementGroup" && -z "$MG_ID" ]]; then
  echo "Error: --management-group-id is required when --scope-type is 'ManagementGroup'." >&2
  usage
  exit 1
fi

# --- Main Execution ---
az account set --subscription "$SUB"

# Ensure resource group exists
if ! az group exists --name "$RG" >/dev/null; then
  echo "Resource group '$RG' not found. Creating it now in location '$LOCATION'..."
  az group create --name "$RG" --location "$LOCATION" >/dev/null
fi

HUB_DEP_NAME="hub-deploy-$(date +%Y%m%d-%H%M%S)"

echo "Step 1: Deploying AVNM hub resources to resource group '$RG'..."
az deployment group create \
  --resource-group "$RG" \
  --name "$HUB_DEP_NAME" \
  --template-file infrastructure/networkmanager/main.bicep \
  --parameters "@$PARAMS_FILE" \
  --verbose

echo "Step 2: Extracting spokes network group IDs from deployment outputs..."
DEV_NG_ID=$(az deployment group show --resource-group "$RG" --name "$HUB_DEP_NAME" --query "properties.outputs.spokesNetworkGroupDevId.value" -o tsv)
TEST_NG_ID=$(az deployment group show --resource-group "$RG" --name "$HUB_DEP_NAME" --query "properties.outputs.spokesNetworkGroupTestId.value" -o tsv)
PROD_NG_ID=$(az deployment group show --resource-group "$RG" --name "$HUB_DEP_NAME" --query "properties.outputs.spokesNetworkGroupProdId.value" -o tsv)

if [[ -z "$DEV_NG_ID" || -z "$TEST_NG_ID" || -z "$PROD_NG_ID" ]]; then
  echo "Error: Could not extract environment network group IDs from deployment outputs. Please check the deployment '$HUB_DEP_NAME' in resource group '$RG'." >&2
  exit 1
fi
echo "Extracted NG IDs: dev=$DEV_NG_ID test=$TEST_NG_ID prod=$PROD_NG_ID"

apply_policy_for_env() {
  local NG_ID="$1"; local ENV_VAL="$2"
  local DISPLAY_NAME="AVNM - Add ${ENV_VAL} Tagged VNets to ${ENV_VAL} Spokes Group"
  local ASSIGN_NAME="avnm-add-${ENV_VAL,,}-tagged-vnets-to-${ENV_VAL,,}-spokes"
  local DEF_NAME="avnm-spoke-tagging-policy-${ENV_VAL,,}"
  local POLICY_PARAMS=(
    "spokesNetworkGroupId=$NG_ID"
    "environment=$ENV_VAL"
    "policyDisplayName=$DISPLAY_NAME"
    "policyAssignmentName=$ASSIGN_NAME"
    "policyDefinitionName=$DEF_NAME"
  )

  echo "Deploying AVNM policy for ${ENV_VAL} at the '${SCOPE_TYPE}' scope..."
  if [[ "$SCOPE_TYPE" == "ManagementGroup" ]]; then
    az deployment mg create \
      --name "avnm-mg-policy-${ENV_VAL}-$(date +%Y%m%d-%H%M%S)" \
      --location "$LOCATION" \
      --management-group-id "$MG_ID" \
      --template-file infrastructure/networkmanager/modules/mg-avnm-policy.bicep \
      --parameters "${POLICY_PARAMS[@]}" \
      --verbose
  else # Default to Subscription
    # When scope is subscription, apply to all subscriptions defined in the parameters file
    MANAGED_SCOPE_IDS=$(jq -r '.parameters.managedScopeIds.value[]' "$PARAMS_FILE")
    for TARGET_SUB in $MANAGED_SCOPE_IDS; do
        echo "Assigning ${ENV_VAL} policy at subscription: ${TARGET_SUB}"
        az account set --subscription "$TARGET_SUB"
        az deployment sub create \
          --name "avnm-sub-policy-${ENV_VAL}-$(date +%Y%m%d-%H%M%S)" \
          --location "$LOCATION" \
          --template-file infrastructure/networkmanager/modules/avnm-policy.bicep \
          --parameters "${POLICY_PARAMS[@]}" \
          --verbose
    done
  fi
}

# Apply policy for Development, Test, Production using extracted NG IDs
apply_policy_for_env "$DEV_NG_ID" "Development"
apply_policy_for_env "$TEST_NG_ID" "Test"
apply_policy_for_env "$PROD_NG_ID" "Production"

echo "Done."
