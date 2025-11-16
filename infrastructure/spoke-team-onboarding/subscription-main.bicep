/*
  ====================================================================
  FILE:     subscription-main.bicep (Team Onboarding - Subscription Mode)
  SCOPE:    Subscription
  DESC:     Onboards a team within the current subscription by creating
            a Resource Group and a VNet per the provided environment,
            using AVNM IPAM to allocate address space.
  ====================================================================
*/

targetScope = 'subscription'

// === PARAMETERS ===

@description('The Azure region to deploy the spoke VNet resources into.')
param location string

@description('Environment name (Development, Test, Production).')
param environment string

@description('The Resource ID of the AVNM IPAM Pool (from hub deployment output).')
@secure()
@minLength(10)
param ipamPoolId string

@description('The name of the spoke Resource Group to create or use if it already exists.')
param spokeResourceGroupName string

@description('The size of the VNet as a CIDR bit (e.g., 24 for a /24).')
@allowed([ 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28 ])
param vnetSizeInBits int = 24


@description('Resource tags object merged onto VNet and RG.')
param resourceTags object = {}

@description('Optional: VNet name to use if existing or to create when missing.')
param vnetName string = ''

// Idempotent behavior:
// - If a VNet named `vnetName` exists in `spokeResourceGroupName`, it is updated
// - If it does not exist, it is created and allocated from IPAM

// === MODULES ===
module spokeInfra 'modules/spoke-infra-deploy.bicep' = {
  name: 'deploy-spoke-${environment}'
  params: {
    location: location
    environment: environment
    ipamPoolId: ipamPoolId
    vnetSizeInBits: vnetSizeInBits
    resourceTags: resourceTags
    spokeRgName: spokeResourceGroupName
    vnetName: vnetName
  }
}

// === OUTPUTS ===
@description('Echo the deployment mode used.')
output onboardingMode string = 'subscription'