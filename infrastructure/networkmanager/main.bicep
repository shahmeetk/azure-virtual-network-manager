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

@description('The full Resource ID of the existing Hub VNet.')
@secure()
param hubVnetId string

@description('List of subscription IDs or subscription resource IDs that define the AVNM management scope.')
param subscriptionIds array

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

@description('Connectivity: allow spokes to use hub gateway (transit to on-prem).')
param useHubGateway bool = true

@description('Connectivity: treat configuration as global across regions.')
param isGlobalConnectivity bool = false

@description('Connectivity: delete pre-existing manual peerings when applying.')
param deleteExistingPeering bool = true

// --- Policy deployment scope parameters (to drive scripts/unified policy module) ---
@description('Policy scope type. Use "Subscription" (default) or "ManagementGroup". This template does not use it directly but accepts it so the parameter file can drive scripts.')
param policyScopeType string = 'Subscription'

@description('Subscription ID to use when policyScopeType = "Subscription". Accepted for parameter file completeness; not used directly by this template.')
param policySubscriptionId string = ''

@description('Management Group ID to use when policyScopeType = "ManagementGroup". Accepted for parameter file completeness; not used directly by this template.')
param policyManagementGroupId string = ''



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
    subscriptionIds: subscriptionIds
    ipamPoolPrefix: ipamPoolPrefix
    hubVnetId: hubVnetId
  }
}

// Note: connectivity-autoprobe module deprecated; using native Bicep connectivity in avnm-configs module.

@description('Module 3: Deploys AVNM Configurations (Connectivity, Routing, Security Admin).')
module avnmConfigs 'modules/avnm-configs.bicep' = {
  name: 'deploy-avnm-configs'
  dependsOn: [
    avnmCore
  ]
  params: {
    avnmName: avnmCore.outputs.avnmName
    hubVnetId: hubVnetId
    spokesNetworkGroupId: avnmCore.outputs.spokesNetworkGroupId
    deployConnectivity: deployConnectivity
    firewallPrivateIpAddress: firewallPrivateIpAddress
    internalSupernet: internalSupernet
    useHubGateway: useHubGateway
    isGlobalConnectivity: isGlobalConnectivity
    deleteExistingPeering: deleteExistingPeering
  }
}

// === OUTPUTS ===
@description('The Resource ID of the deployed AVNM instance.')
output avnmId string = avnmCore.outputs.avnmId

@description('The Resource ID of the IPAM Pool. This is a REQUIRED INPUT for the team-onboarding.bicep template.')
output ipamPoolId string = avnmCore.outputs.ipamPoolId

@description('The Resource ID of the Hub Network Group (static).')
output hubNetworkGroupId string = avnmCore.outputs.hubNetworkGroupId

@description('The Resource ID of the Spokes Network Group (dynamic).')
output spokesNetworkGroupId string = avnmCore.outputs.spokesNetworkGroupId

// === ADDITIONAL OUTPUTS FROM MINIMAL CONFIGS MODULE ===
@description('Security Admin Configuration ID (if deployed).')
output securityAdminConfigId string = avnmConfigs.outputs.securityAdminConfigId

@description('Security Admin Rule Collection ID (if deployed).')
output securityAdminRuleCollectionId string = avnmConfigs.outputs.securityAdminRuleCollectionId

@description('Security Admin Rule ID (if deployed).')
output securityAdminRuleId string = avnmConfigs.outputs.securityAdminRuleId
