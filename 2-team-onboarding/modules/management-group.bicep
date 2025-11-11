// == PURPOSE ==
// This module creates a management group for team organization.
// It handles management group creation with proper validation and error handling.
// == PARAMETERS ==
@description('Name of the team.')
@minLength(1)
@maxLength(50)
@pattern('^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$')
param teamName string

@description('Parent management group ID.')
@minLength(1)
@maxLength(100)
param parentManagementGroupId string

@description('Tags to apply to the management group.')
param tags object = {}

// == VARIABLES ==
var managementGroupName = '${teamName}-mg'
var sanitizedTeamName = replace(replace(teamName, ' ', '-'), '_', '-')

// == RESOURCES ==
@description('Create team management group')
resource teamManagementGroup 'Microsoft.Management/managementGroups@2023-04-01' = {
  name: managementGroupName
  properties: {
    displayName: 'MG - ${sanitizedTeamName}'
    details: {
      parent: {
        id: '/providers/Microsoft.Management/managementGroups/${parentManagementGroupId}'
      }
    }
  }
}

// == OUTPUTS ==
@description('The ID of the created management group.')
output teamManagementGroupId string = teamManagementGroup.id

@description('The name of the created management group.')
output teamManagementGroupName string = teamManagementGroup.name