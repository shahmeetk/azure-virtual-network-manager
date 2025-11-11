/*
  ====================================================================
  FILE:     subscription-main.bicep (Team Onboarding - Subscription Mode)
  SCOPE:    Subscription
  DESC:     Onboards a team within the current subscription by creating
            a Resource Group and a VNet per environment using AVNM IPAM.
  ====================================================================
*/

targetScope = 'subscription'

// === PARAMETERS ===
@description('Short, unique name for the new team (e.g., "TeamA"). Used for naming.')
@minLength(2)
@maxLength(10)
@pattern('^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$')
param teamName string

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

@description('Array of environment names. A spoke VNet will be created for each.')
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

@description('Tag name used by AVNM policy to auto-onboard VNets to the Spokes Network Group (optional).')
param includeTagName string = 'avnm-group'

@description('Tag value used by AVNM policy to auto-onboard VNets to the Spokes Network Group (optional).')
param includeTagValue string = 'spokes'

// === RESOURCES ===

@description('Deploy spoke infrastructure (Resource Group + VNet) for each environment in the current subscription')
module spokeInfra 'modules/spoke-infra-deploy.bicep' = [for env in environments: {
  name: 'deploy-spoke-${teamName}-${env}'
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
@description('Deployment mode used.')
output onboardingMode string = 'subscription'