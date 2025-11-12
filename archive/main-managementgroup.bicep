/*
  ====================================================================
  FILE:     main.bicep (Team Onboarding)
  SCOPE:    Tenant (/)
  DESC:     Orchestrates the end-to-end onboarding of a new team.
            1. Creates a new Management Group for the team.
            2. Creates N new subscriptions (dev, uat, prod) in that MG.
            3. Deploys a VNet from the AVNM IPAM pool into each new sub.
  ====================================================================
*/

// This template MUST be deployed at the Tenant scope [12]
targetScope = 'tenant'

// === PARAMETERS ===
@description('Short, unique name for the new team (e.g., "TeamA"). Used for naming.')
@minLength(2)
@maxLength(10)
@pattern('^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$')
param teamName string

@description('Onboarding mode: "managementGroup" (create MG + subscriptions) or "subscription" (use current subscription).')
@allowed([
  'managementGroup'
  'subscription'
])
param onboardingMode string = 'managementGroup'

@description('The ID of the parent Management Group to place the new team MG under.')
@minLength(1)
@maxLength(100)
param parentManagementGroupId string

@description('The full Resource ID of the billing scope for new subscriptions. [13, 14]')
@secure()
@minLength(10)
param billingScope string

@description('The Azure region to deploy the spoke VNet resources into.')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'canadacentral'
  'canadaeast'
  'australiaeast'
  'australiasoutheast'
  'japaneast'
  'japanwest'
  'southeastasia'
  'eastasia'
])
param location string

@description('Array of environment names. A subscription will be created for each.')
@allowed([
  'dev'
  'uat'
  'prod'
  'test'
  'staging'
])
param environments array = [
  'dev'
  'uat'
  'prod'
]

@description('The Resource ID of the AVNM IPAM Pool (from hub-deploy output).')
@secure()
@minLength(10)
param ipamPoolId string

@description('The size of the VNet as a CIDR bit (e.g., 24 for a /24).')
@allowed([ 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28 ])
param vnetSizeInBits int = 24

@description('Maximum number of retry attempts for subscription creation (passed to module).')
@minValue(1)
@maxValue(10)
param maxRetries int = 3

@description('Delay in seconds between retry attempts (passed to module).')
@minValue(30)
@maxValue(300)
param retryDelaySeconds int = 60

@description('Enable detailed logging for subscription creation process (passed to module).')
param enableLogging bool = true

@description('Tag name used by AVNM policy to auto-onboard VNets to the Spokes Network Group (optional).')
param includeTagName string = 'avnm-group'

@description('Tag value used by AVNM policy to auto-onboard VNets to the Spokes Network Group (optional).')
param includeTagValue string = 'spokes'

// === VARIABLES ===
var teamMgName = 'mg-${teamName}'

// === RESOURCES ===

@description('Module: Create team Management Group')
module teamMg 'modules/management-group.bicep' = if (onboardingMode == 'managementGroup') {
  name: 'deploy-team-mg'
  scope: managementGroup('${parentManagementGroupId}')
  params: {
    teamName: teamName
    parentManagementGroupId: parentManagementGroupId
  }
}

@description('Module: Create subscriptions for each environment with retry logic')
module subscriptionCreation 'modules/subscription-creation.bicep' = if (onboardingMode == 'managementGroup') [for env in environments: {
  name: 'create-subscription-${teamName}-${env}'
  scope: tenant()
  params: {
    subscriptionName: '${teamName}-${env}'
    billingScope: billingScope
    managementGroupId: teamMg.outputs.teamManagementGroupId
    tags: {
      Team: teamName
      Environment: env
      Purpose: 'Team onboarding'
      ManagedBy: 'Azure Enterprise Bicep'
      CreatedDate: utcNow('yyyy-MM-dd')
    }
    maxRetries: maxRetries
    retryDelaySeconds: retryDelaySeconds
    enableLogging: enableLogging
  }
}]

@description('Module: Deploy spoke infrastructure (Resource Group + VNet)')
module spokeInfra 'modules/spoke-infra-deploy.bicep' = [for (env, i) in environments: {
  name: 'deploy-spoke-${teamName}-${env}'
  scope: onboardingMode == 'managementGroup'
    ? subscription(subscriptionCreation[i].outputs.subscriptionId)
    : subscription()
  params: {
    location: location
    teamName: teamName
    environment: env
    ipamPoolId: ipamPoolId
    vnetSizeInBits: vnetSizeInBits
    includeTagName: includeTagName
    includeTagValue: includeTagValue
  }
}]

// === OUTPUTS ===
@description('The ID of the new Team Management Group (empty in subscription mode).')
output teamManagementGroupId string = onboardingMode == 'managementGroup' ? teamMg.outputs.teamManagementGroupId : ''

@description('Information about created subscriptions by environment (present only in managementGroup mode).')
output subscriptions array = onboardingMode == 'managementGroup'
  ? [for (env, i) in environments: {
      environment: env
      name: subscriptionCreation[i].outputs.subscriptionName
      subscriptionId: subscriptionCreation[i].outputs.subscriptionId
    }]
  : []