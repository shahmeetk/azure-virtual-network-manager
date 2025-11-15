/*
  ====================================================================
  FILE:     main.bicep (Hub Platform Deployment)
  SCOPE:    Resource Group
  DESC:     Deploys the central Azure Virtual Network Manager (AVNM)
            and all its components (IPAM, Groups, Configs, Policy).
            This template is run ONCE.
  ====================================================================
*/

// Bicep Target Scope: This template deploys to a Resource Group
targetScope = 'resourceGroup'

// === PARAMETERS ===
@description('The Azure region where the AVNM and hub resources will be deployed.')
param location string = resourceGroup().location

@description('A short, unique prefix for naming all central platform resources.')
@minLength(3)
@maxLength(10)
param prefix string

// @description('The name of the existing Azure Firewall in the hub.')
// @minLength(1)
// @maxLength(80)
// param hubFirewallName string

// @description('The name of the Resource Group containing the existing Azure Firewall.')
// @minLength(1)
// @maxLength(90)
// param hubFirewallRgName string

@description('Hub Resource Group name')
param hubResourceGroupName string

@description('Hub VNet name')
param hubVnetName string

@description('Hub VNet size in bits (e.g., 20 for /20)')
@allowed([16,17,18,19,20,21,22,23,24,25,26,27,28])
param hubVnetSizeInBits int = 20

@description('Hub subscription ID')
param hubSubscriptionId string

@description('Managed scope type for spokes')
@allowed(['Subscription','ManagementGroup'])
param managedScopeType string = 'Subscription'

@description('Managed scope ID (subscription GUID or management group ID)')
param managedScopeId string

@description('The static CIDR block for the entire IPAM pool (e.g., "10.0.0.0/10").')
param ipamPoolPrefix string

@description('Toggle: whether to deploy the AVNM connectivity configuration now. Set to false while we stabilize, then true later.')
param deployConnectivity bool = false

@description('Optional: Hub firewall private IP. When set with internalSupernet, routing is enabled to force spoke traffic via firewall.')
param firewallPrivateIpAddress string = ''

@description('Optional: Internal supernet (e.g., IPAM pool CIDR). When provided with firewallPrivateIpAddress, forces spoke-to-spoke via firewall.')
param internalSupernet string = ''

@description('Tag name used by policy to auto-onboard spokes (default avnm-group).')
param includeTagName string = 'avnm-group'

@description('Tag value used by policy to auto-onboard spokes (default spokes).')
param includeTagValue string = 'spokes'

@description('Deployment environment')
@allowed(['Development','Test','Production'])
param environment string

@description('Description tag value')
param descriptionTag string = ''

@description('Created Date tag value (yyyy-mm-dd)')
param createdDateTag string = ''

@description('Resource tags object')
param resourceTags object = {}

@description('Connectivity: allow spokes to use hub gateway (transit to on-prem).')
param useHubGateway bool = true

@description('Connectivity: treat configuration as global across regions.')
param isGlobalConnectivity bool = false

@description('Connectivity: delete pre-existing manual peerings when applying.')
param deleteExistingPeering bool = true



// === EXISTING RESOURCES ===
// (Disabled for minimal deployment; firewall is optional)
// @description('Reference to the existing Azure Firewall to retrieve its private IP for routing.')
// resource existingFirewall 'Microsoft.Network/azureFirewalls@2023-11-01' existing = {
//   scope: resourceGroup(hubFirewallRgName)
//   name: hubFirewallName
// }

// === MODULES ===

@description('Module 1: Deploys Core AVNM Resources (AVNM, IPAM Pool, Network Groups).')
module avnmCore 'modules/avnm-core.bicep' = {
  name: 'deploy-avnm-core'
  params: {
    location: location
    prefix: prefix
    hubSubscriptionId: hubSubscriptionId
    managedScopeType: managedScopeType
    managedScopeId: managedScopeId
    ipamPoolPrefix: ipamPoolPrefix
    hubVnetId: resolvedHubVnetId
  }
}

// Note: connectivity-autoprobe module deprecated; using native Bicep connectivity in avnm-configs module.

@description('Module 3: Deploys AVNM Configurations (Connectivity, Routing, Security Admin).')
module avnmConfigs 'modules/avnm-configs.bicep' = {
  name: 'deploy-avnm-configs'
  params: {
    avnmName: avnmCore.outputs.avnmName
    hubVnetId: resolvedHubVnetId
    spokesNetworkGroupIds: [
      avnmCore.outputs.spokesNetworkGroupDevId
      avnmCore.outputs.spokesNetworkGroupTestId
      avnmCore.outputs.spokesNetworkGroupProdId
    ]
    deployConnectivity: deployConnectivity
    firewallPrivateIpAddress: firewallPrivateIpAddress
    internalSupernet: internalSupernet
    useHubGateway: useHubGateway
    isGlobalConnectivity: isGlobalConnectivity
    deleteExistingPeering: deleteExistingPeering
  }
}

var hubVnetIpCount = hubVnetSizeInBits == 16 ? '65536'
  : hubVnetSizeInBits == 17 ? '32768'
  : hubVnetSizeInBits == 18 ? '16384'
  : hubVnetSizeInBits == 19 ? '8192'
  : hubVnetSizeInBits == 20 ? '4096'
  : hubVnetSizeInBits == 21 ? '2048'
  : hubVnetSizeInBits == 22 ? '1024'
  : hubVnetSizeInBits == 23 ? '512'
  : hubVnetSizeInBits == 24 ? '256'
  : hubVnetSizeInBits == 25 ? '128'
  : hubVnetSizeInBits == 26 ? '64'
  : hubVnetSizeInBits == 27 ? '32'
  : hubVnetSizeInBits == 28 ? '16'
  : '4096'

@description('Create Hub VNet if missing (controlled by script)')
param createHubVnetIfMissing bool = false

module hubVnet 'modules/vnet-from-ipam.bicep' = if (createHubVnetIfMissing) {
  name: 'create-hub-vnet'
  params: {
    location: location
    vnetName: hubVnetName
    ipamPoolId: avnmCore.outputs.ipamPoolId
    numberOfIpAddresses: hubVnetIpCount
    environment: environment
    includeTagValue: includeTagValue
    includeTagName: includeTagName
    descriptionTag: descriptionTag
    createdDateTag: createdDateTag
    resourceTags: resourceTags
    virtualNetworkAddressPrefixes: []
  }
}

// Create static hub member after AVNM core and (if used) hub VNet creation
resource avnmExisting 'Microsoft.Network/networkManagers@2024-10-01' existing = {
  name: avnmName
}
resource hubNetworkGroupExisting 'Microsoft.Network/networkManagers/networkGroups@2024-10-01' existing = {
  parent: avnmExisting
  name: '${prefix}-ng-hub-static'
}
resource hubStaticMember 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-10-01' = {
  parent: hubNetworkGroupExisting
  name: 'hub-vnet-member'
  properties: {
    resourceId: resolvedHubVnetId
  }
  dependsOn: createHubVnetIfMissing ? [ avnmCore, hubVnet ] : [ avnmCore ]
}

// Resolve Hub VNet ID from name and RG via an existing resource reference
resource existingHubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  scope: resourceGroup(hubResourceGroupName)
  name: hubVnetName
}
var resolvedHubVnetId = existingHubVnet.id

// === OUTPUTS ===
@description('The Resource ID of the deployed AVNM instance.')
output avnmId string = avnmCore.outputs.avnmId

@description('The Resource ID of the IPAM Pool. This is a REQUIRED INPUT for the team-onboarding.bicep template.')
output ipamPoolId string = avnmCore.outputs.ipamPoolId

@description('The Resource ID of the Hub Network Group (static).')
output hubNetworkGroupId string = avnmCore.outputs.hubNetworkGroupId

@description('The Resource ID of the Spokes Network Group (dynamic).')
output spokesNetworkGroupDevId string = avnmCore.outputs.spokesNetworkGroupDevId
output spokesNetworkGroupTestId string = avnmCore.outputs.spokesNetworkGroupTestId
output spokesNetworkGroupProdId string = avnmCore.outputs.spokesNetworkGroupProdId

// === ADDITIONAL OUTPUTS FROM MINIMAL CONFIGS MODULE ===
@description('Security Admin Configuration ID (if deployed).')
output securityAdminConfigId string = avnmConfigs.outputs.securityAdminConfigId

@description('Security Admin Rule Collection ID (if deployed).')
output securityAdminRuleCollectionId string = avnmConfigs.outputs.securityAdminRuleCollectionId

@description('Security Admin Rule ID (if deployed).')
output securityAdminRuleId string = avnmConfigs.outputs.securityAdminRuleId
var avnmName = '${prefix}-avnm'
