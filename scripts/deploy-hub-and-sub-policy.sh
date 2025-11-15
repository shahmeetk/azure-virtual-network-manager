#!/usr/bin/env bash
# Orchestrator: Deploy hub (RG scope) and AVNM policy (Subscription by default; optional MG)
set -euo pipefail

# --- Defaults ---
SUB=""
RG=""
LOCATION=""
PARAMS_FILE=""
INCLUDE_TAG_NAME="Environment"
INCLUDE_TAG_VALUE="Development"
SECONDARY_TAG_NAME="avnm-group"
SECONDARY_TAG_VALUE="spokes"
SCOPE_TYPE="Subscription"
MG_ID=""
HUB_VNET_NAME=""

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
  --hub-vnet-name <VNET>          (Optional) Hub VNet name; if missing, will create via IPAM.
  --scope-type <TYPE>             (Optional) The scope for the policy assignment. Can be 'Subscription' or 'ManagementGroup'. Defaults to 'Subscription'.
  --management-group-id <MG_ID>   (Optional) The management group ID, required if --scope-type is 'ManagementGroup'.
  -h, --help                      Show this help message.
EOF
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="$2"; shift 2;;
    --resource-group) RG="$2"; shift 2;;
    --location) LOCATION="$2"; shift 2;;
    --params) PARAMS_FILE="$2"; shift 2;;
    --scope-type) SCOPE_TYPE="$2"; shift 2;;
    --management-group-id) MG_ID="$2"; shift 2;;
    --hub-vnet-name) HUB_VNET_NAME="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# --- Validation ---
if [[ -z "$SUB" || -z "$RG" || -z "$LOCATION" || -z "$PARAMS_FILE" ]]; then
  echo "Error: Missing required arguments. Use -h or --help for usage details." >&2
  exit 1
fi

if [[ "$SCOPE_TYPE" == "ManagementGroup" && -z "$MG_ID" ]]; then
  echo "Error: --management-group-id is required when --scope-type is 'ManagementGroup'." >&2
  exit 1
fi

# --- Main Execution ---
az account set --subscription "$SUB"

# Ensure resource group exists
if ! az group exists --name "$RG" >/dev/null; then
  az group create --name "$RG" --location "$LOCATION" >/dev/null
fi

HUB_DEP_NAME="hub-deploy-$(date +%Y%m%d-%H%M%S)"

echo "Step 1: Deploying AVNM hub resources to resource group '$RG'..."
if [[ ! -f "$PARAMS_FILE" ]]; then
  echo "Warning: parameters file '$PARAMS_FILE' not found. Falling back to infrastructure/networkmanager/main.parameters.json" >&2
  PARAMS_FILE="infrastructure/networkmanager/main.parameters.json"
fi

HUB_RG_FROM_FILE=$(jq -r '.parameters.hubResourceGroupName.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
HUB_VNET_NAME_FROM_FILE=$(jq -r '.parameters.hubVnetName.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
if [[ -n "$HUB_RG_FROM_FILE" ]]; then RG="$HUB_RG_FROM_FILE"; fi
if [[ -z "$HUB_VNET_NAME" && -n "$HUB_VNET_NAME_FROM_FILE" ]]; then HUB_VNET_NAME="$HUB_VNET_NAME_FROM_FILE"; fi

VNET_EXISTS=false
if [[ -n "$HUB_VNET_NAME" ]]; then
  if az network vnet show -g "$RG" -n "$HUB_VNET_NAME" >/dev/null 2>&1; then
    VNET_EXISTS=true
  fi
fi

EXTRA_PARAMS=()
if [[ "$VNET_EXISTS" == false ]]; then
  EXTRA_PARAMS+=("createHubVnetIfMissing=true")
fi

az deployment group create \
  --resource-group "$RG" \
  --name "$HUB_DEP_NAME" \
  --template-file infrastructure/networkmanager/main.bicep \
  --parameters @"$PARAMS_FILE" ${EXTRA_PARAMS[@]} \
  --verbose

echo "Step 2: Extracting spokes network group ID from deployment outputs..."
DEV_NG_ID=$(az deployment group show --resource-group "$RG" --name "$HUB_DEP_NAME" --query "properties.outputs.spokesNetworkGroupDevId.value" -o tsv)
TEST_NG_ID=$(az deployment group show --resource-group "$RG" --name "$HUB_DEP_NAME" --query "properties.outputs.spokesNetworkGroupTestId.value" -o tsv)
PROD_NG_ID=$(az deployment group show --resource-group "$RG" --name "$HUB_DEP_NAME" --query "properties.outputs.spokesNetworkGroupProdId.value" -o tsv)

if [[ -z "$DEV_NG_ID" || -z "$TEST_NG_ID" || -z "$PROD_NG_ID" ]]; then
  echo "Error: Could not extract environment network group IDs from deployment outputs. Please check the deployment '$HUB_DEP_NAME' in resource group '$RG'." >&2
  exit 1
fi
echo "Extracted NG IDs: dev=$DEV_NG_ID test=$TEST_NG_ID prod=$PROD_NG_ID"

# --- CRITICAL VALIDATION STEP ---
echo "Step 2a: Validating that the extracted ID contains the correct resource group name..."
if [[ ! "$DEV_NG_ID" == *"/resourceGroups/$RG/"* || ! "$TEST_NG_ID" == *"/resourceGroups/$RG/"* || ! "$PROD_NG_ID" == *"/resourceGroups/$RG/"* ]]; then
  echo "FATAL ERROR: The extracted Spokes Network Group ID does not belong to the correct resource group!" >&2
  echo "  Expected Resource Group: $RG" >&2
  echo "  Found IDs: $DEV_NG_ID | $TEST_NG_ID | $PROD_NG_ID" >&2
  echo "  This indicates that the Azure CLI is returning a stale output from a previous deployment. Please try clearing your Azure CLI cache or re-running the script." >&2
  exit 1
fi
echo "Validation passed. All IDs belong to resource group '$RG'."


echo "Step 3: Deploying AVNM policy at the '$SCOPE_TYPE' scope..."

# Read tag parameters from the same hub parameters file (fallback to defaults)
INCLUDE_TAG_NAME_FROM_FILE=$(jq -r '.parameters.includeTagName.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
INCLUDE_TAG_VALUE_FROM_FILE=$(jq -r '.parameters.includeTagValue.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
if [[ -n "$INCLUDE_TAG_NAME_FROM_FILE" ]]; then INCLUDE_TAG_NAME="$INCLUDE_TAG_NAME_FROM_FILE"; fi
if [[ -n "$INCLUDE_TAG_VALUE_FROM_FILE" ]]; then INCLUDE_TAG_VALUE="$INCLUDE_TAG_VALUE_FROM_FILE"; fi

# Validate tag parameters
if [[ -z "$INCLUDE_TAG_NAME" || -z "$INCLUDE_TAG_VALUE" ]]; then
  echo "Error: includeTagName/includeTagValue are missing. Set them in $PARAMS_FILE or via defaults in script." >&2
  exit 1
fi

# Validate required new parameters for template
HUB_SUB_ID_FROM_FILE=$(jq -r '.parameters.hubSubscriptionId.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
MANAGED_SCOPE_TYPE_FROM_FILE=$(jq -r '.parameters.managedScopeType.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
MANAGED_SCOPE_ID_FROM_FILE=$(jq -r '.parameters.managedScopeId.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
if [[ -z "$HUB_SUB_ID_FROM_FILE" ]]; then
  echo "Error: hubSubscriptionId is missing in $PARAMS_FILE." >&2
  exit 1
fi

# Align scope type with parameters when provided
if [[ -n "$MANAGED_SCOPE_TYPE_FROM_FILE" ]]; then
  SCOPE_TYPE="$MANAGED_SCOPE_TYPE_FROM_FILE"
fi
if [[ "$SCOPE_TYPE" == "ManagementGroup" ]]; then
  if [[ -z "$MG_ID" && -n "$MANAGED_SCOPE_ID_FROM_FILE" ]]; then
    MG_ID="$MANAGED_SCOPE_ID_FROM_FILE"
  fi
  if [[ -z "$MG_ID" ]]; then
    echo "Error: Management Group scope requested but management group ID is missing (provide --management-group-id or managedScopeId in params)." >&2
    exit 1
  fi
fi

# Proactively remove any existing custom policy definition/assignment to avoid stale linked scopes
true

apply_policy_for_env() {
  local NG_ID="$1"; local ENV_VAL="$2"
  local DISPLAY_NAME="AVNM - Add ${ENV_VAL} Tagged VNets to ${ENV_VAL} Spokes Group"
  local ASSIGN_NAME="avnm-add-${ENV_VAL,,}-tagged-vnets-to-${ENV_VAL,,}-spokes"
  local DEF_NAME="avnm-spoke-tagging-policy-${ENV_VAL,,}"
  local POLICY_PARAMS=(
    "spokesNetworkGroupId=$NG_ID"
    "includeTagName=$INCLUDE_TAG_NAME"
    "includeTagValue=$ENV_VAL"
    "secondaryIncludeTagName=$SECONDARY_TAG_NAME"
    "secondaryIncludeTagValue=$SECONDARY_TAG_VALUE"
    "policyDisplayName=$DISPLAY_NAME"
    "policyAssignmentName=$ASSIGN_NAME"
    "policyDefinitionName=$DEF_NAME"
  )

  # Flexible scope: `managedScopeId` can be an array of subscriptions OR a single management group ID OR a single subscription ID
  local TARGET_SCOPE_VALUE=$(jq -r '.parameters.managedScopeId.value // empty' "$PARAMS_FILE" 2>/dev/null || true)
  local TARGET_SCOPE_TYPE=$(jq -r '.parameters.managedScopeId.value | type' "$PARAMS_FILE" 2>/dev/null || true)
  local SUB_LIST=()
  local EFFECTIVE_SCOPE="${SCOPE_TYPE}"
  local EFFECTIVE_MG_ID="$MG_ID"

  if [[ -n "$TARGET_SCOPE_VALUE" && "$TARGET_SCOPE_VALUE" != "null" ]]; then
    if [[ "$TARGET_SCOPE_TYPE" == "array" ]]; then
      mapfile -t SUB_LIST < <(jq -r '.parameters.managedScopeId.value[]' "$PARAMS_FILE" 2>/dev/null || true)
      EFFECTIVE_SCOPE="Subscription"
    elif [[ "$TARGET_SCOPE_TYPE" == "string" ]]; then
      if [[ "$TARGET_SCOPE_VALUE" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        SUB_LIST=("$TARGET_SCOPE_VALUE")
        EFFECTIVE_SCOPE="Subscription"
      elif [[ "$TARGET_SCOPE_VALUE" == /subscriptions/* ]]; then
        local SUB_ID_EXTRACTED
        SUB_ID_EXTRACTED=$(echo "$TARGET_SCOPE_VALUE" | awk -F'/subscriptions/' '{print $2}' | awk -F'/' '{print $1}')
        SUB_LIST=("$SUB_ID_EXTRACTED")
        EFFECTIVE_SCOPE="Subscription"
      else
        EFFECTIVE_SCOPE="ManagementGroup"
        EFFECTIVE_MG_ID="$TARGET_SCOPE_VALUE"
      fi
    fi
  fi

  echo "Deploying AVNM policy at the '${EFFECTIVE_SCOPE}' scope..."
  if [[ "$EFFECTIVE_SCOPE" == "ManagementGroup" ]]; then
    az policy assignment delete --name "$ASSIGN_NAME" --scope "/providers/Microsoft.Management/managementGroups/${EFFECTIVE_MG_ID}" 2>/dev/null || true
    az policy definition delete --name "$DEF_NAME" 2>/dev/null || true
    az deployment mg create \
      --name "avnm-mg-policy-${ENV_VAL}-$(date +%Y%m%d-%H%M%S)" \
      --location "$LOCATION" \
      --management-group-id "$EFFECTIVE_MG_ID" \
      --template-file infrastructure/networkmanager/modules/mg-avnm-policy.bicep \
      --parameters "${POLICY_PARAMS[@]}" \
      --verbose
  else
    if [[ ${#SUB_LIST[@]} -gt 0 ]]; then
      for TARGET_SUB in "${SUB_LIST[@]}"; do
        echo "Assigning ${ENV_VAL} policy at subscription: ${TARGET_SUB}"
        az account set --subscription "$TARGET_SUB"
        az policy assignment delete --name "$ASSIGN_NAME" 2>/dev/null || true
        az policy definition delete --name "$DEF_NAME" 2>/dev/null || true
        az deployment sub create \
          --name "avnm-sub-policy-${ENV_VAL}-$(date +%Y%m%d-%H%M%S)" \
          --location "$LOCATION" \
          --template-file infrastructure/networkmanager/modules/avnm-policy.bicep \
          --parameters "${POLICY_PARAMS[@]}" \
          --verbose
      done
    else
      az policy assignment delete --name "$ASSIGN_NAME" 2>/dev/null || true
      az policy definition delete --name "$DEF_NAME" 2>/dev/null || true
      az deployment sub create \
        --name "avnm-sub-policy-${ENV_VAL}-$(date +%Y%m%d-%H%M%S)" \
        --location "$LOCATION" \
        --template-file infrastructure/networkmanager/modules/avnm-policy.bicep \
        --parameters "${POLICY_PARAMS[@]}" \
        --verbose
    fi
  fi
}

# Apply policy for Development, Test, Production using extracted NG IDs
INCLUDE_TAG_NAME=${INCLUDE_TAG_NAME:-environment}
# Ensure secondary tag is the spokes grouping tag
SECONDARY_TAG_NAME=${SECONDARY_TAG_NAME:-avnm-group}
SECONDARY_TAG_VALUE=${SECONDARY_TAG_VALUE:-spokes}
# Use Pascal case values for environment tag to match your convention
apply_policy_for_env "$DEV_NG_ID" "Development"
apply_policy_for_env "$TEST_NG_ID" "Test"
apply_policy_for_env "$PROD_NG_ID" "Production"

echo "Done."
