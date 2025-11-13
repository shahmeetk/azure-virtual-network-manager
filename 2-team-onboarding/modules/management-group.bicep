/*
  ====================================================================
  MODULE:   management-group.bicep
  SCOPE:    Tenant
  DESC:     Creates a new management group under a specified parent.
  ====================================================================
*/

targetScope = 'tenant'

// === PARAMETERS ===
@description('The unique name for the new management group. This is the ID, not the display name.')
@minLength(3)
@maxLength(24)
param managementGroupName string

@description('The friendly display name for the new management group.')
@minLength(1)
param managementGroupDisplayName string

@description('The ID of the parent management group.')
param parentManagementGroupId string

// === RESOURCES ===
@description('Creates the team-specific management group.')
resource teamManagementGroup 'Microsoft.Management/managementGroups@2023-04-01' = {
  name: managementGroupName
  properties: {
    displayName: managementGroupDisplayName
    details: {
      parent: {
        id: '/providers/Microsoft.Management/managementGroups/${parentManagementGroupId}'
      }
    }
  }
}

// === OUTPUTS ===
@description('The full resource ID of the created management group.')
output managementGroupId string = teamManagementGroup.id

@description('The name (ID) of the created management group.')
output managementGroupName string = teamManagementGroup.name
