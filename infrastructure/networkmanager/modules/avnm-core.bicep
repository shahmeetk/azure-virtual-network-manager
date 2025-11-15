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

@description('List of subscription IDs or subscription resource IDs to scope AVNM to (e.g., "<subId>" or "/subscriptions/<subId>").')
param subscriptionIds array

@description('The static CIDR block for the entire IPAM pool.')
param ipamPoolPrefix string

@description('Name of the IPAM pool to create or reference. Use a stable name to ensure a single pool (e.g., "<prefix>-ipam-pool").')
param ipamPoolName string = '${prefix}-ipam-pool'

@description('If true, this deployment will manage (create/update) the IPAM pool. If false, the template will not attempt to modify it (useful when a pool already exists with a different prefix).')
param manageIpamPool bool = true


// === VARIABLES ===
var avnmName = '${prefix}-avnm'
var hubNetworkGroupName = '${prefix}-ng-hub-static'
var spokesNetworkGroupName = '${prefix}-ng-spokes-dynamic'
var subscriptionResourceIds = [for sid in subscriptionIds: startsWith(sid, '/subscriptions/') ? sid : '/subscriptions/${sid}']


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
      subscriptions: subscriptionResourceIds
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

@description('4a. Add the Hub VNet as a static member.')
resource hubStaticMember 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-10-01' = {
  parent: hubNetworkGroup
  name: 'hub-vnet-member'
  properties: {
    resourceId: hubVnetId
  }
}

@description('5. Create the Network Group for all Spokes (Dynamic Membership).')
resource spokesNetworkGroup 'Microsoft.Network/networkManagers/networkGroups@2024-10-01' = {
  parent: avnm
  name: spokesNetworkGroupName
  properties: {
    description: 'Dynamic group for all tagged spoke VNets.'
  }
}

// === OUTPUTS ===
output avnmId string = avnm.id
output avnmName string = avnm.name
output ipamPoolId string = manageIpamPool ? ipamPool.id : ipamPoolExisting.id
output hubNetworkGroupId string = hubNetworkGroup.id
output hubStaticMemberId string = hubStaticMember.id
output spokesNetworkGroupId string = spokesNetworkGroup.id