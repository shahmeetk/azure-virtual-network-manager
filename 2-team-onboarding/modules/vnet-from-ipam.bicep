/*
  ====================================================================
  MODULE:   vnet-from-ipam.bicep
  SCOPE:    Resource Group
  DESC:     Deploys a single VNet, drawing its CIDR
            from the central AVNM IPAM Pool. [21, 20]
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
param numberOfIpAddresses string // [19, 20]

@description('Tag: Team name.')
param teamName string

@description('Tag: Environment name.')
param environment string

@description('Tag name used by policy to auto-onboard spokes (default avnm-group).')
param includeTagName string = 'avnm-group'

@description('Tag value used by policy to auto-onboard spokes (default spokes).')
param includeTagValue string = 'spokes'

// === RESOURCES ===

@description('Deploy the Virtual Network using IPAM for address allocation.')
resource vnet 'Microsoft.Network/virtualNetworks@2024-10-01' = {
  name: vnetName
  location: location
  tags: {
    Team: teamName
    Environment: environment
    // Tag used by AVNM subscription policy to auto-onboard this VNet to Spokes NG
    [includeTagName]: includeTagValue
  }
  properties: {
    // We DO NOT define 'addressPrefixes'
    // Instead, AVNM IPAM will allocate a non-overlapping prefix. [19, 20, 22]
    // Use json() to supply a payload the service accepts, while bypassing strict type validation
    // in the Bicep type definition for AddressSpace.
    addressSpace: json('{"ipamPoolPrefixAllocations":[{"pool":{"id":"${ipamPoolId}"},"numberOfIpAddresses":"${numberOfIpAddresses}"}]}')
    subnets: [] // Empty subnets array for initial deployment
  }
}

// === OUTPUTS ===
@description('The ID of the newly created VNet.')
output vnetId string = vnet.id

@description('The (dynamically allocated) address prefixes of the new VNet (array).')
output allocatedAddressPrefixes array = vnet.properties.addressSpace.addressPrefixes
