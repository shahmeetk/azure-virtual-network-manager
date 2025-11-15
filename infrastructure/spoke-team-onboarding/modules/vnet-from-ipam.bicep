/*
  ====================================================================
  MODULE:   vnet-from-ipam.bicep
  SCOPE:    Resource Group
  DESC:     Deploys a single VNet, drawing its CIDR
            from the central AVNM IPAM Pool.
  ====================================================================
*/

targetScope = 'resourceGroup'

// === PARAMETERS ===
@description('The Azure region.')
param location string

@description('The name for the new Virtual Network.')
param vnetName string

@description('The Resource ID of the AVNM IPAM Pool.')
param ipamPoolId string

@description('The number of IP addresses for the VNet (e.g., "256").')
param numberOfIpAddresses string

@description('Tag: Team name.')
param teamName string

@description('Tag: Environment name.')
param environment string

@description('Tag value used by policy to auto-onboard spokes (default spokes).')
param includeTagValue string = 'spokes'

@description('Tag name used by policy to auto-onboard spokes (default avnm-group).')
param includeTagName string = 'avnm-group'

// === RESOURCES ===

@description('Deploy the Virtual Network using IPAM for address allocation.')
resource vnet 'Microsoft.Network/virtualNetworks@2024-10-01' = {
  name: vnetName
  location: location
  tags: {
    Team: teamName
    Environment: environment
    '${includeTagName}': includeTagValue
  }
  properties: {
    addressSpace: json('{"ipamPoolPrefixAllocations":[{"pool":{"id":"${ipamPoolId}"},"numberOfIpAddresses":"${numberOfIpAddresses}"}]}')
    subnets: []
  }
}

// === OUTPUTS ===
@description('The ID of the newly created VNet.')
output vnetId string = vnet.id

@description('The (dynamically allocated) address prefixes of the new VNet (array).')
output allocatedAddressPrefixes array = vnet.properties.addressSpace.addressPrefixes