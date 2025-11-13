#!/usr/bin/env bash
# Orchestrator: Deploy hub (RG scope) and AVNM policy (Subscription by default; optional MG)
set -euo pipefail

# --- Defaults ---
SUB=""
RG=""
LOCATION=""
PARAMS_FILE=""
INCLUDE_TAG_NAME="avnm-group"
INCLUDE_TAG_VALUE="spokes"
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

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="$2"; shift 2;;
    --resource-group) RG="$2"; shift 2;;
    --location) LOCATION="$2"; shift 2;;
    --params) PARAMS_FILE="$2"; shift 2;;
    --scope-type) SCOPE_TYPE="$2"; shift 2;;
    --management-group-id) MG_ID="$2"; shift 2;;
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

HUB_DEP_NAME="hub-deploy-$(date +%Y%m%d-%H%M%S)"

echo "Step 1: Deploying AVNM hub resources to resource group '$RG'..."
az deployment group create \
  --resource-group "$RG" \
  --name "$HUB_DEP_NAME" \
  --template-file 1-platform-deployment/hub/main.bicep \
  --parameters @"$PARAMS_FILE" \
  --parameters policySubscriptionId="$SUB" \
  --verbose

echo "Step 2: Extracting spokes network group ID from deployment outputs..."
SPOKES_NG_ID=$(az deployment group show --resource-group "$RG" --name "$HUB_DEP_NAME" --query "properties.outputs.spokesNetworkGroupId.value" -o tsv)

if [[ -z "$SPOKES_NG_ID" ]]; then
  echo "Error: Could not extract spokesNetworkGroupId from deployment outputs. Please check the deployment '$HUB_DEP_NAME' in resource group '$RG'." >&2
  exit 1
fi
echo "Successfully extracted Spokes Network Group ID: $SPOKES_NG_ID"

# --- CRITICAL VALIDATION STEP ---
echo "Step 2a: Validating that the extracted ID contains the correct resource group name..."
if [[ ! "$SPOKES_NG_ID" == *"/resourceGroups/$RG/"* ]]; then
  echo "FATAL ERROR: The extracted Spokes Network Group ID does not belong to the correct resource group!" >&2
  echo "  Expected Resource Group: $RG" >&2
  echo "  Found ID: $SPOKES_NG_ID" >&2
  echo "  This indicates that the Azure CLI is returning a stale output from a previous deployment. Please try clearing your Azure CLI cache or re-running the script." >&2
  exit 1
fi
echo "Validation passed. The ID belongs to resource group '$RG'."


echo "Step 3: Deploying AVNM policy at the '$SCOPE_TYPE' scope..."

# Proactively remove any existing custom policy definition/assignment to avoid stale linked scopes
if [[ "$SCOPE_TYPE" == "ManagementGroup" ]]; then
  # Delete MG-scope assignment/definition if present (ignore errors)
  az policy assignment delete --name avnm-add-tagged-vnets-to-spokes --scope "/providers/Microsoft.Management/managementGroups/${MG_ID}" 2>/dev/null || true
  az policy definition delete --name avnm-mg-spoke-tagging-policy 2>/dev/null || true
else
  # Delete subscription-scope assignment/definition if present (ignore errors)
  az policy assignment delete --name avnm-add-tagged-vnets-to-spokes 2>/dev/null || true
  az policy definition delete --name avnm-spoke-tagging-policy 2>/dev/null || true
fi

POLICY_PARAMS=(
  "spokesNetworkGroupId=$SPOKES_NG_ID"
  "includeTagName=$INCLUDE_TAG_NAME"
  "includeTagValue=$INCLUDE_TAG_VALUE"
)

if [[ "$SCOPE_TYPE" == "ManagementGroup" ]]; then
  az deployment mg create \
    --name "avnm-mg-policy-$(date +%Y%m%d-%H%M%S)" \
    --location "$LOCATION" \
    --management-group-id "$MG_ID" \
    --template-file 1-platform-deployment/hub/modules/mg-avnm-policy.bicep \
    --parameters "${POLICY_PARAMS[@]}" \
    --verbose
else # Default to Subscription
  az deployment sub create \
    --name "avnm-sub-policy-$(date +%Y%m%d-%H%M%S)" \
    --location "$LOCATION" \
    --template-file 1-platform-deployment/hub/modules/avnm-policy.bicep \
    --parameters "${POLICY_PARAMS[@]}" \
    --verbose
fi

echo "Done."
