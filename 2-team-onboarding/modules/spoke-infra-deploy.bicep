/*
  ====================================================================
  MODULE:   spoke-infra-deploy.bicep
  SCOPE:    Subscription
  DESC:     Deploys the initial infrastructure (RG, VNet)
            into a newly created subscription.
  ====================================================================
*/

// This module runs at the Subscription scope [18]
targetScope = 'subscription'

// === PARAMETERS ===
@description('The Azure region to deploy resources into.')
param location string

@description('Short name for the team.')
param teamName string

@description('The environment (dev, uat, prod).')
param environment string

@description('The Resource ID of the AVNM IPAM Pool.')
param ipamPoolId string

@description('The size of the VNet as a CIDR bit (e.g., 24).')
param vnetSizeInBits int

// === VARIABLES ===
var rgName = 'rg-${teamName}-${environment}-net'
var vnetName = 'vnet-${teamName}-${environment}'
// Calculate the number of IPs (e.g., /24 = 2^(32-24) = 256) and convert to string for the API [19, 20]
var vnetSizeAsNumberString = string(pow(2, 32 - vnetSizeInBits))

// === RESOURCES ===

@description('1. Create the Resource Group for the spoke network.')
resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: {
    Team: teamName
    Environment: environment
  }
}

@description('2. Deploy the VNet using the IPAM-enabled module.')
module vnetDeploy 'vnet-from-ipam.bicep' = {
  name: 'deploy-${vnetName}'
  // This module is scoped to the new Resource Group [1, 16]
  scope: resourceGroup(spokeRg.name)
  params: {
    location: location
    vnetName: vnetName
    ipamPoolId: ipamPoolId
    numberOfIpAddresses: vnetSizeAsNumberString
    teamName: teamName
    environment: environment
  }
}
