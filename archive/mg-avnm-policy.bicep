/*
  ====================================================================
  FILE:     mg-avnm-policy.bicep
  STATUS:   DEPRECATED (moved)
  --------------------------------------------------------------------
  This file has been moved to:
    1-platform-deployment/hub/modules/mg-avnm-policy.bicep

  Please update any references to use the new path. This placeholder is
  kept temporarily for backward compatibility and will be removed.
  ====================================================================
*/

targetScope = 'managementGroup'

@description('Management Group ID (name, not display name). This is the scope where policy will be deployed.')
param parentManagementGroupId string

@description('The Spokes Network Group resource ID (from Hub deployment outputs).')
param spokesNetworkGroupId string

@description('Optional: A tag name used to include VNets. Default: avnm-group')
param includeTagName string = 'avnm-group'

@description('Optional: A tag value used to include VNets. Default: spokes')
param includeTagValue string = 'spokes'

@description('Policy definition display name')
param policyDisplayName string = 'AVNM - Add Tagged VNets to Spokes Group'

@description('Policy assignment name (lowercase letters, numbers, and hyphens).')
@minLength(3)
@maxLength(64)
param policyAssignmentName string = 'avnm-add-tagged-vnets-to-spokes'

@description('Custom Policy Definition for AVNM addToNetworkGroup at management group scope')
resource policyDef 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: 'avnm-mg-spoke-tagging-policy'
  properties: {
    displayName: policyDisplayName
    description: 'Adds any VNet with the tag "${includeTagName}" = "${includeTagValue}" to the AVNM Spokes Network Group.'
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

@description('Policy Assignment at management group scope')
resource policyAssign 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: policyAssignmentName
  properties: {
    displayName: policyDisplayName
    policyDefinitionId: policyDef.id
  }
}

@description('Policy Assignment ID')
output policyAssignmentId string = policyAssign.id

targetScope = 'managementGroup'

@description('Management Group ID (name, not display name). This is the scope where policy will be deployed.')
param parentManagementGroupId string

@description('The Spokes Network Group resource ID (from Hub deployment outputs).')
param spokesNetworkGroupId string

@description('Optional: A tag name used to include VNets. Default: avnm-group')
param includeTagName string = 'avnm-group'

@description('Optional: A tag value used to include VNets. Default: spokes')
param includeTagValue string = 'spokes'

@description('Policy definition display name')
param policyDisplayName string = 'AVNM - Add Tagged VNets to Spokes Group'

@description('Policy assignment name (lowercase letters, numbers, and hyphens).')
@minLength(3)
@maxLength(64)
param policyAssignmentName string = 'avnm-add-tagged-vnets-to-spokes'

@description('Custom Policy Definition for AVNM addToNetworkGroup at management group scope')
resource policyDef 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: 'avnm-mg-spoke-tagging-policy'
  properties: {
    displayName: policyDisplayName
    description: 'Adds any VNet with the tag "${includeTagName}" = "${includeTagValue}" to the AVNM Spokes Network Group.'
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

@description('Policy Assignment at management group scope')
resource policyAssign 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: policyAssignmentName
  properties: {
    displayName: policyDisplayName
    policyDefinitionId: policyDef.id
  }
}

@description('Policy Assignment ID')
output policyAssignmentId string = policyAssign.id
