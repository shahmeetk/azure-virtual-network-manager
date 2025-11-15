/*
  ====================================================================
  MODULE:   avnm-core.bicep
  SCOPE:    Resource Group
  DESC:     Deploys the AVNM instance, IPAM Pool, and Network Groups.
  ====================================================================
*/

targetScope = 'resourceGroup'

@description('The Azure region for all resources.')
param location string

@description('A short, unique prefix for naming all resources.')
param prefix string

@description('The full Resource ID of the existing Hub VNet.')
param hubVnetId string

@description('Hub subscription ID')
param hubSubscriptionId string

@description('Managed scope type for spokes')
@allowed(['Subscription','ManagementGroup'])
param managedScopeType string = 'Subscription'

@description('Managed scope ID (subscription GUID or management group ID)')
param managedScopeId string

@description('The static CIDR block for the entire IPAM pool.')
param ipamPoolPrefix string

@description('Name of the IPAM pool to create or reference. Use a stable name to ensure a single pool (e.g., "<prefix>-ipam-pool").')
param ipamPoolName string = '${prefix}-ipam-pool'

@description('If true, this deployment will manage (create/update) the IPAM pool. If false, the template will not attempt to modify it (useful when a pool already exists with a different prefix).')
param manageIpamPool bool = true


// === VARIABLES ===
var avnmName = '${prefix}-avnm'
var hubNetworkGroupName = '${prefix}-ng-hub-static'
var hubSubscriptionResourceId = startsWith(hubSubscriptionId, '/subscriptions/') ? hubSubscriptionId : '/subscriptions/${hubSubscriptionId}'
var managedSubscriptionResourceId = managedScopeType == 'Subscription' ? (startsWith(managedScopeId, '/subscriptions/') ? managedScopeId : '/subscriptions/${managedScopeId}') : ''
var managedManagementGroupResourceId = managedScopeType == 'ManagementGroup' ? (startsWith(managedScopeId, '/providers/Microsoft.Management/managementGroups/') ? managedScopeId : '/providers/Microsoft.Management/managementGroups/${managedScopeId}') : ''



// === RESOURCES ===


@description('1. Deploy the Azure Virtual Network Manager instance.')
resource avnm 'Microsoft.Network/networkManagers@2024-10-01' = {
  name: avnmName
  location: location
  properties: {
    description: 'Central AVNM for enterprise connectivity and security.'
    networkManagerScopeAccesses: [
      'Connectivity'
      'SecurityAdmin'
      'Routing'
    ]
    networkManagerScopes: {
      subscriptions: managedScopeType == 'Subscription' ? [hubSubscriptionResourceId, managedSubscriptionResourceId] : [hubSubscriptionResourceId]
      managementGroups: managedScopeType == 'ManagementGroup' ? [managedManagementGroupResourceId] : []
    }
  }
}

@description('2. Deploy the IPAM Pool as a child of the AVNM (conditionally).')
resource ipamPool 'Microsoft.Network/networkManagers/ipamPools@2024-10-01' = if (manageIpamPool) {
  parent: avnm
  name: ipamPoolName
  location: location
  properties: {
    description: 'Global IPAM pool for all spokes.'
    addressPrefixes: [
      ipamPoolPrefix
    ]
  }
}

@description('Reference the IPAM pool if it already exists (no changes made).')
resource ipamPoolExisting 'Microsoft.Network/networkManagers/ipamPools@2024-10-01' existing = {
  parent: avnm
  name: ipamPoolName
}

@description('4. Create the Network Group for the Hub VNet (Static Membership).')
resource hubNetworkGroup 'Microsoft.Network/networkManagers/networkGroups@2024-10-01' = {
  parent: avnm
  name: hubNetworkGroupName
  properties: {
    description: 'Static group containing the Hub VNet.'
  }
}

// 4a. Static hub member moved to main.bicep to ensure ordering when hub VNet is created conditionally

@description('5a. Create the Network Group for Dev Spokes')
resource spokesNetworkGroupDev 'Microsoft.Network/networkManagers/networkGroups@2024-10-01' = {
  parent: avnm
  name: '${prefix}-ng-spokes-dev'
  properties: {
    description: 'Dynamic group for Development spokes.'
  }
}

@description('5b. Create the Network Group for Test Spokes')
resource spokesNetworkGroupTest 'Microsoft.Network/networkManagers/networkGroups@2024-10-01' = {
  parent: avnm
  name: '${prefix}-ng-spokes-test'
  properties: {
    description: 'Dynamic group for Test spokes.'
  }
}

@description('5c. Create the Network Group for Prod Spokes')
resource spokesNetworkGroupProd 'Microsoft.Network/networkManagers/networkGroups@2024-10-01' = {
  parent: avnm
  name: '${prefix}-ng-spokes-prod'
  properties: {
    description: 'Dynamic group for Production spokes.'
  }
}

// === OUTPUTS ===
output avnmId string = avnm.id
output avnmName string = avnm.name
output ipamPoolId string = manageIpamPool ? ipamPool.id : ipamPoolExisting.id
output hubNetworkGroupId string = hubNetworkGroup.id
// Static member created in main.bicep; no output here
output spokesNetworkGroupDevId string = spokesNetworkGroupDev.id
output spokesNetworkGroupTestId string = spokesNetworkGroupTest.id
output spokesNetworkGroupProdId string = spokesNetworkGroupProd.id