/*
  ====================================================================
  MODULE:   hub-vnet.bicep
  SCOPE:    Resource Group
  DESC:     Deploys the Hub Virtual Network.
  ====================================================================
*/

targetScope = 'resourceGroup'

// === PARAMETERS ===
@description('The Azure region for the VNet.')
param location string

@description('The name of the Hub VNet.')
param hubVnetName string

@description('The address space for the Hub VNet (e.g., "10.0.0.0/16").')
param hubVnetAddressPrefix string

@description('Tags to apply to the VNet.')
param tags object = {}

// === RESOURCES ===
@description('The Hub Virtual Network.')
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: hubVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressPrefix
      ]
    }
    // Add subnets here if needed, e.g., for Gateway, Firewall, etc.
    subnets: []
  }
  tags: tags
}

// === OUTPUTS ===
@description('The full resource ID of the deployed Hub VNet.')
output vnetId string = hubVnet.id

@description('The name of the deployed Hub VNet.')
output vnetName string = hubVnet.name
