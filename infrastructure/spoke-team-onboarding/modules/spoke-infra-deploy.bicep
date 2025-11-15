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


@description('Tag value used by policy to auto-onboard spokes (optional).')
param includeTagValue string = 'spokes'

@description('Tag name used by policy to auto-onboard spokes (optional).')
param includeTagName string = 'avnm-group'

@description('The name of the spoke Resource Group to create or use if it exists.')
param spokeRgName string

// === VARIABLES ===
var vnetName = 'vnet-${spokeRgName}-${environment}'
// Map CIDR size to number of IP addresses as a string (Bicep lacks pow())
var vnetSizeAsNumberString = vnetSizeInBits == 16 ? '65536'
  : vnetSizeInBits == 17 ? '32768'
  : vnetSizeInBits == 18 ? '16384'
  : vnetSizeInBits == 19 ? '8192'
  : vnetSizeInBits == 20 ? '4096'
  : vnetSizeInBits == 21 ? '2048'
  : vnetSizeInBits == 22 ? '1024'
  : vnetSizeInBits == 23 ? '512'
  : vnetSizeInBits == 24 ? '256'
  : vnetSizeInBits == 25 ? '128'
  : vnetSizeInBits == 26 ? '64'
  : vnetSizeInBits == 27 ? '32'
  : vnetSizeInBits == 28 ? '16'
  : '256'

// === RESOURCES ===

@description('1. Create the Resource Group for the spoke network.')
resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: spokeRgName
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
    includeTagValue: includeTagValue
    includeTagName: includeTagName
  }
}