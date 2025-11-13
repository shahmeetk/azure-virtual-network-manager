/*
  ====================================================================
  FILE:     main.bicep (Team Onboarding)
  SCOPE:    Management Group
  DESC:     Orchestrates the creation of resources for new teams,
            including management groups and subscriptions.
  ====================================================================
*/

// This template should be deployed at the management group level that will contain the new team MGs.
targetScope = 'managementGroup'

// === PARAMETERS ===
@description('The parent management group ID where the new team management groups will be created.')
param parentManagementGroupId string = managementGroup().id

@description('The full resource ID of the billing account scope for new subscriptions.')
@secure()
param billingAccountScope string

@description('An array of team objects to onboard. Each object should define the team name and desired subscription display name.')
param teams array = []

// === MAIN ORCHESTRATION ===

@description('Loop through each team to create their dedicated management group.')
module teamManagementGroups 'modules/management-group.bicep' = [for (team, i) in teams: {
  name: 'deploy-mg-${team.name}-${i}'
  scope: tenant() // Management groups are tenant-level resources
  params: {
    managementGroupName: '${team.name}-mg'
    managementGroupDisplayName: 'MG for ${team.name}'
    parentManagementGroupId: parentManagementGroupId
  }
}]

@description('Loop through each team to create their subscription.')
module subscriptionCreation 'modules/subscription-creation.bicep' = [for (team, i) in teams: {
  name: 'deploy-sub-${team.name}-${i}'
  scope: tenant() // Subscriptions are created at the tenant level
  dependsOn: [
    teamManagementGroups[i] // Ensure the MG exists before placing a sub in it
  ]
  params: {
    subscriptionAliasName: '${team.name}-sub-alias-${uniqueString(team.name)}'
    subscriptionDisplayName: team.subscriptionDisplayName
    billingAccountScope: billingAccountScope
    targetManagementGroupId: teamManagementGroups[i].outputs.managementGroupId
  }
}]

// === OUTPUTS ===
@description('The outputs from the management group module deployments.')
output managementGroupDeployments array = [for (team, i) in teams: {
  teamName: team.name
  managementGroupId: teamManagementGroups[i].outputs.managementGroupId
}]

@description('The outputs from the subscription creation module deployments.')
output subscriptionDeployments array = [for (team, i) in teams: {
  teamName: team.name
  subscriptionAliasName: subscriptionCreation[i].outputs.subscriptionAliasName
}]
