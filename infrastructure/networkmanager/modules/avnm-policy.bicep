/*
  ====================================================================
  MODULE:   avnm-policy.bicep
  SCOPE:    Subscription
  DESC:     Policy Definition & Assignment to auto-onboard tagged
            VNets into the AVNM Spokes Network Group using the
            addToNetworkGroup effect (Microsoft.Network.Data mode).
            Use mg-avnm-policy.bicep for Management Group scope.
  ====================================================================
*/

// This template is intended for Subscription deployments
targetScope = 'subscription'

@description('The Spokes Network Group resource ID (from hub deployment outputs).')
param spokesNetworkGroupId string

@description('Tag name used to include VNets (default: avnm-group).')
param includeTagName string = 'avnm-group'

@description('Tag value used to include VNets (default: spokes).')
param includeTagValue string = 'spokes'

@description('Secondary tag name used to include VNets (default: avnm-group).')
param secondaryIncludeTagName string = 'avnm-group'

@description('Secondary tag value used to include VNets (default: spokes).')
param secondaryIncludeTagValue string = 'spokes'

@description('Policy definition display name')
param policyDisplayName string = 'AVNM - Add Tagged VNets to Spokes Group'

@description('Policy assignment name (lowercase letters, numbers, and hyphens).')
@minLength(3)
@maxLength(64)
param policyAssignmentName string = 'avnm-add-tagged-vnets-to-spokes'

@description('Policy definition resource name (unique per environment)')
param policyDefinitionName string = 'avnm-spoke-tagging-policy'

resource policyDef 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: policyDefinitionName
  properties: {
    displayName: policyDisplayName
    description: 'Adds any VNet with tags "${includeTagName}" = "${includeTagValue}" AND "${secondaryIncludeTagName}" = "${secondaryIncludeTagValue}" to the AVNM Spokes Network Group.'
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
          {
            field: format('tags[{0}]', secondaryIncludeTagName)
            equals: secondaryIncludeTagValue
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

@description('Policy Assignment at subscription scope')
resource policyAssign 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: policyAssignmentName
  properties: {
    displayName: policyDisplayName
    policyDefinitionId: policyDef.id
  }
}

@description('Policy Assignment ID')
output policyAssignmentId string = policyAssign.id