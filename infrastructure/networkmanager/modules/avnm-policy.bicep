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

@description('Environment tag value used to include VNets (Development, Test, Production).')
@allowed(['Development','Test','Production'])
param environment string
// Matches VNets with tags:
// - Environment = <environment>
// - avnm-group = spokes

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
    description: 'Adds any VNet tagged with Environment = "${environment}" and avnm-group = "spokes" to the AVNM Spokes Network Group.'
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
            field: 'tags[Environment]'
            equals: environment
          }
          {
            field: 'tags[avnm-group]'
            equals: 'spokes'
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