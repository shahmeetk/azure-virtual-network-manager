/*
  ====================================================================
  MODULE:   connectivity-autoprobe.bicep
  STATUS:   DEPRECATED — DO NOT USE
  --------------------------------------------------------------------
  This module has been superseded by modules/avnm-configs.bicep, which
  now provisions the AVNM Connectivity Configuration natively via Bicep
  (api-version 2024-10-01) together with Routing and Security Admin.

  The hub deployment no longer references this module. It is retained
  temporarily for backward compatibility and will be removed.
  ====================================================================
*/

targetScope = 'resourceGroup'

@description('[DEPRECATED] Azure region for the script runtime/storage.')
param location string

@description('[DEPRECATED] AVNM resource name (e.g., test-avnm).')
param avnmName string

@description('[DEPRECATED] Full resource ID of the Hub VNet to use as the hub in connectivity.')
param hubVnetId string

@description('[DEPRECATED] This module is deprecated; flag left for no-op compatibility (defaults to false).')
param enableConnectivity bool = false

var rgName = resourceGroup().name
var subId  = subscription().subscriptionId
var baseUri = '/subscriptions/${subId}/resourceGroups/${rgName}/providers/Microsoft.Network/networkManagers/${avnmName}/connectivityConfigurations/cc-hub-and-spoke'

@description('[DEPRECATED] Azure CLI deployment script to create connectivity configuration by probing supported API versions.')
// Create a user-assigned identity for the script and grant Contributor at RG scope
resource scriptUai 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = if (enableConnectivity) {
  name: 'uai-connectivity-autoprobe'
  location: location
}

resource scriptUaiContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableConnectivity) {
  name: guid(resourceGroup().id, scriptUai.name, 'conn-autoprobe-contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: scriptUai.properties.principalId
  }
}

resource script 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (enableConnectivity) {
  name: 'connectivity-autoprobe'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptUai.id}': {}
    }
  }
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.58.0'
    timeout: 'PT15M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    environmentVariables: [
      { name: 'BASE_URI', value: baseUri }
      { name: 'HUB_VNET_ID', value: hubVnetId }
    ]
    scriptContent: '''
echo "[DEPRECATED] connectivity-autoprobe.bicep is deprecated. Use modules/avnm-configs.bicep."
exit 0
'''
  }
}

@description('Legacy script body retained below for reference only (never executed).')
resource script_legacy 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (false) {
  name: 'connectivity-autoprobe-legacy'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.58.0'
    timeout: 'PT10M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    environmentVariables: []
    scriptContent: '''
set -euo pipefail
APIS=("2024-05-01" "2024-07-01" "2024-10-01")

try_variant() {
  local api="$1"; local variant="$2"
  case "$variant" in
    1)
      body=$(jq -n --arg id "$HUB_VNET_ID" '{properties:{connectivityTopology:"HubAndSpoke", hubs:[{resourceId:$id}]}}')
      ;;
    2)
      body=$(jq -n --arg id "$HUB_VNET_ID" '{properties:{connectivityTopology:"HubAndSpoke", groupConnectivity:"None", hubs:[{resourceId:$id}]}}')
      ;;
    3)
      # Some tenants only accept minimal bodies first; appliesToGroups will be added later via a small patch if needed.
      body=$(jq -n --arg id "$HUB_VNET_ID" '{properties:{connectivityTopology:"HubAndSpoke", groupConnectivity:"None", hubs:[{resourceId:$id}]}}')
      ;;
    *) return 2;;
  esac
  uri="${BASE_URI}?api-version=${api}"
  if out=$(az rest --method put --uri "$uri" --body "$body" 2>&1); then
    echo "Succeeded api=${api} variant=${variant}" >&2
    echo "$out" | jq -r .properties | tr -d '\r' > $AZ_SCRIPTS_OUTPUT_PATH
    return 0
  else
    echo "Failed api=${api} variant=${variant}" >&2
    echo "$out" >&2
    return 1
  fi
}

for api in "${APIS[@]}"; do
  for variant in 1 2 3; do
    if try_variant "$api" "$variant"; then
      exit 0
    fi
  done
done
# If we reach here, all variants failed. Emit a small JSON so the deployment captures this.
echo '{"status":"Failed","reason":"All connectivity variants failed (tenant backend mapping error)"}' > $AZ_SCRIPTS_OUTPUT_PATH
exit 0
'''
  }
}

@description('[DEPRECATED] Script result.')
output result string = enableConnectivity ? string(script.properties.outputs) : ''

/*
MANUAL FALLBACK (only if needed; do NOT run if the script above succeeds):

# Replace values and run one of the following from your shell to try a single call.
az rest --method put \
  --uri "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Network/networkManagers/<AVNM>/connectivityConfigurations/cc-hub-and-spoke?api-version=2024-10-01" \
  --body @- <<'JSON'
{ "properties": { "connectivityTopology": "HubAndSpoke", "hubs": [ { "resourceId": "<HUB_VNET_ID>" } ] } }
JSON

# If that fails, try with groupConnectivity
az rest --method put \
  --uri "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Network/networkManagers/<AVNM>/connectivityConfigurations/cc-hub-and-spoke?api-version=2024-07-01" \
  --body @- <<'JSON'
{ "properties": { "connectivityTopology": "HubAndSpoke", "groupConnectivity": "None", "hubs": [ { "resourceId": "<HUB_VNET_ID>" } ] } }
JSON
*/
