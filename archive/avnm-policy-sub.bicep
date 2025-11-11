/*
  ====================================================================
  MODULE:   avnm-policy-sub.bicep
  STATUS:   DEPRECATED — use modules/avnm-policy.bicep instead
  SCOPE:    Subscription
  DESC:     This legacy module is superseded by the unified
            modules/avnm-policy.bicep which supports both
            Subscription and Management Group scopes via parameters.
  ====================================================================
*/

targetScope = 'subscription'

@description('The Spokes Network Group resource ID (from Hub deployment outputs).')
param spokesNetworkGroupId string

@description('Optional: A tag name used to include VNets. Default: avnm-group')
param includeTagName string = 'avnm-group'

@description('Optional: A tag value used to include VNets. Default: spokes')
param includeTagValue string = 'spokes'

@description('Policy definition display name')
param policyDisplayName string = 'AVNM (Sub) - Add Tagged VNets to Spokes Group'

@description('Policy assignment name (lowercase letters, numbers, and hyphens).')
@minLength(3)
@maxLength(64)
param policyAssignmentName string = 'avnm-sub-add-tagged-vnets-to-spokes'

var policyDefinitionName = 'avnm-sub-spoke-tagging-policy'

@description('Custom Policy Definition for AVNM addToNetworkGroup at subscription scope')
resource policyDef 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: policyDefinitionName
  properties: {
    displayName: policyDisplayName
    description: 'Adds any VNet with the tag "${includeTagName}" = "${includeTagValue}" to the central AVNM Spokes Network Group.'
    policyType: 'Custom'
    mode: 'Microsoft.Network.Data'
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Network/virtualNetworks'
          }
          {
            field: format('tags[{0}]', includeTagName)
            equals: includeTagValue
          }
        ]
      }
      then: {
        effect: 'addToNetworkGroup'
        details: {
          networkGroupId: spokesNetworkGroupId
        }
      }
    }
  }
}

@description('Policy Assignment at current subscription scope')
resource policyAssign 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: policyAssignmentName
  properties: {
    displayName: policyDisplayName
    policyDefinitionId: policyDef.id
  }
}

@description('Policy Assignment ID (subscription)')
output policyAssignmentId string = policyAssign.id

// NOTE: Please migrate to the unified module:
//   azure-enterprise-bicep/1-platform-deployment/hub/modules/avnm-policy.bicep
// Usage (subscription): scopeType="Subscription", subscriptionId="<subId>", includeTagName/value via parameters
