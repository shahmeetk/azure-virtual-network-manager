/*
  ====================================================================
  MODULE:   avnm-core.bicep
  SCOPE:    Resource Group
  DESC:     Deploys the AVNM instance, IPAM Pool, and Network Groups.
  ====================================================================
*/

targetScope = 'resourceGroup'

// === PARAMETERS ===
@description('The Azure region for all resources.')
param location string

@description('A short, unique prefix for naming all resources.')
param prefix string

@description('The subscription ID where the hub VNet resides.')
param hubSubscriptionId string

@description('The type of scope AVNM will manage for spokes.')
@allowed(['Subscription','ManagementGroup'])
param managedScopeType string = 'Subscription'

@description('An array of subscription IDs or a single management group ID that AVNM will manage.')
param managedScopeIds array

@description('The static CIDR block for the entire IPAM pool.')
param ipamPoolPrefix string

// === VARIABLES ===
var avnmName = '${prefix}-avnm'
var ipamPoolName = '${prefix}-ipam-pool'
var hubNetworkGroupName = '${prefix}-ng-hub-static'
var spokesNetworkGroupDevName = '${prefix}-ng-spokes-development'
var spokesNetworkGroupTestName = '${prefix}-ng-spokes-test'
var spokesNetworkGroupProdName = '${prefix}-ng-spokes-production'

var subscriptionResourceIds = [for subId in union([hubSubscriptionId], managedScopeType == 'Subscription' ? managedScopeIds : []): '/subscriptions/${subId}']
var managementGroupResourceIds = [for mgId in (managedScopeType == 'ManagementGroup' ? managedScopeIds : []): '/providers/Microsoft.Management/managementGroups/${mgId}']

// === RESOURCES ===

@description('1. Deploy the Azure Virtual Network Manager instance.')
resource avnm 'Microsoft.Network/networkManagers@2024-05-01' = {
  name: avnmName
  location: location
  properties: {
    description: 'Central AVNM for enterprise connectivity and security.'
    networkManagerScopeAccesses: [ 'Connectivity', 'SecurityAdmin', 'Routing' ]
    networkManagerScopes: {
      subscriptions: subscriptionResourceIds
      managementGroups: managementGroupResourceIds
    }
  }
}

@description('2. Deploy the IPAM Pool as a child of the AVNM.')
resource ipamPool 'Microsoft.Network/networkManagers/ipamPools@2024-05-01' = {
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

@description('4. Create the Network Group for the Hub VNet (Static Membership).')
resource hubNetworkGroup 'Microsoft.Network/networkManagers/networkGroups@2024-05-01' = {
  parent: avnm
  name: hubNetworkGroupName
  properties: {
    description: 'Static group containing the Hub VNet.'
  }
}

@description('5a. Create the Network Group for Dev Spokes')
resource spokesNetworkGroupDev 'Microsoft.Network/networkManagers/networkGroups@2024-05-01' = {
  parent: avnm
  name: spokesNetworkGroupDevName
  properties: {
    description: 'Dynamic group for Development spokes.'
  }
}

@description('5b. Create the Network Group for Test Spokes')
resource spokesNetworkGroupTest 'Microsoft.Network/networkManagers/networkGroups@2024-05-01' = {
  parent: avnm
  name: spokesNetworkGroupTestName
  properties: {
    description: 'Dynamic group for Test spokes.'
  }
}

@description('5c. Create the Network Group for Prod Spokes')
resource spokesNetworkGroupProd 'Microsoft.Network/networkManagers/networkGroups@2024-05-01' = {
  parent: avnm
  name: spokesNetworkGroupProdName
  properties: {
    description: 'Dynamic group for Production spokes.'
  }
}

// === OUTPUTS ===
output avnmId string = avnm.id
output avnmName string = avnm.name
output ipamPoolId string = ipamPool.id
output hubNetworkGroupId string = hubNetworkGroup.id
output spokesNetworkGroupDevId string = spokesNetworkGroupDev.id
output spokesNetworkGroupTestId string = spokesNetworkGroupTest.id
output spokesNetworkGroupProdId string = spokesNetworkGroupProd.id
