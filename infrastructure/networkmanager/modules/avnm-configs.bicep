/*
  ====================================================================
  MODULE:   avnm-configs.bicep
  SCOPE:    Resource Group
  DESC:     Deploys AVNM Configurations (Connectivity, Routing, Security).
  ====================================================================
*/

targetScope = 'resourceGroup'

// === PARAMETERS ===
@description('The name of the AVNM instance (from avnm-core.bicep).')
param avnmName string

@description('The full Resource ID of the Hub VNet that acts as the hub in the connectivity configuration.')
param hubVnetId string

@description('The Resource ID of the Spokes Network Group.')
param spokesNetworkGroupId string

@description('Whether to deploy the Connectivity Configuration. Set true only after backend acceptance is verified.')
param deployConnectivity bool = false

@description('If true, spokes use the hub gateway for transit (recommended for hub-and-spoke).')
param useHubGateway bool = true

@description('If true, configuration is global across regions. Keep false for single-region deployments.')
param isGlobalConnectivity bool = false

@description('If true, delete any existing manual peerings when applying connectivity.')
param deleteExistingPeering bool = true

@description('The private IP address of the existing Hub Firewall. Optional; when empty, routing resources are skipped.')
param firewallPrivateIpAddress string = ''

@description('The internal supernet (IPAM pool) to force-route to the firewall. Optional; when empty, routing resources are skipped.')
param internalSupernet string = ''

@description('Name for the connectivity configuration.')
param connectivityConfigName string = 'hub-and-spoke-connectivity'

@description('Name for the routing configuration.')
param routingConfigName string = 'rc-force-all-traffic-to-firewall'

@description('Name for the routing rule collection.')
param routeRuleCollectionName string = 'rc-collection-default'

@description('Name for the security admin configuration.')
param securityAdminConfigName string = 'sac-global-baseline'

@description('Name for the security admin rule collection.')
param securityAdminRuleCollectionName string = 'sc-baseline-rules'

// Routing is enabled only when both firewall IP and internal supernet are provided.
var enableRouting = !empty(firewallPrivateIpAddress) && !empty(internalSupernet)

// === EXISTING RESOURCES ===
@description('Reference to the parent AVNM resource.')
resource avnm 'Microsoft.Network/networkManagers@2024-07-01' existing = {
  name: avnmName
}

// === RESOURCES ===

@description('1. Connectivity Configuration (Hub-and-Spoke).')
resource connConfig 'Microsoft.Network/networkManagers/connectivityConfigurations@2024-07-01' = if (deployConnectivity) {
  parent: avnm
  name: connectivityConfigName
  properties: {
    connectivityTopology: 'HubAndSpoke'
    hubs: [
      {
        // Explicitly declare hub resource type and id for clarity
        resourceType: 'Microsoft.Network/virtualNetworks'
        resourceId: hubVnetId
      }
    ]
    appliesToGroups: [
      {
        networkGroupId: spokesNetworkGroupId
        groupConnectivity: 'None'
        useHubGateway: useHubGateway ? 'True' : 'False'
        isGlobal: isGlobalConnectivity ? 'True' : 'False'
      }
    ]
    deleteExistingPeering: deleteExistingPeering ? 'True' : 'False'
    isGlobal: isGlobalConnectivity ? 'True' : 'False'
    connectivityCapabilities: {
      connectedGroupPrivateEndpointsScale: 'Standard'
      connectedGroupAddressOverlap: 'Allowed'
      peeringEnforcement: 'Unenforced'
    }
  }
}

@description('2. Routing Configuration (Force Traffic to Firewall).')
resource routeConfig 'Microsoft.Network/networkManagers/routingConfigurations@2024-07-01' = if (enableRouting) {
  parent: avnm
  name: routingConfigName
  properties: {
    description: 'Forces all spoke traffic (Internet and Spoke-to-Spoke) to the hub firewall.'
  }
}

// === OUTPUTS ===
@description('Connectivity configuration ID for commit operations.')
output connectivityConfigurationId string = deployConnectivity ? connConfig.id : ''

@description('Routing configuration ID for commit operations (if enabled).')
output routingConfigurationId string = enableRouting ? routeConfig.id : ''

@description('Security admin configuration ID for commit operations.')
output securityAdminConfigurationId string = secConfig.id

@description('2a. Define the Rule Collection for the Routing Configuration.')
resource routeRuleCollection 'Microsoft.Network/networkManagers/routingConfigurations/ruleCollections@2024-07-01' = if (enableRouting) {
  parent: routeConfig
  name: routeRuleCollectionName
  properties: {
    appliesTo: [
      {
        networkGroupId: spokesNetworkGroupId
      }
    ]
  }
}

@description('2b. Rule to force Internet-bound traffic to the firewall.')
resource routeRuleDefault 'Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-07-01' = if (enableRouting) {
  parent: routeRuleCollection
  name: 'rule-default-to-firewall'
  properties: {
    description: 'Route 0.0.0.0/0 to Hub Firewall'
    destination: {
      destinationAddress: '0.0.0.0/0'
      type: 'AddressPrefix'
    }
    nextHop: {
      nextHopType: 'VirtualAppliance'
      nextHopAddress: firewallPrivateIpAddress
    }
  }
}

@description('2c. Rule to force Spoke-to-Spoke traffic to the firewall.')
resource routeRuleInternal 'Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-07-01' = if (enableRouting) {
  parent: routeRuleCollection
  name: 'rule-internal-to-firewall'
  properties: {
    description: 'Route all internal spoke-to-spoke traffic to Hub Firewall'
    destination: {
      destinationAddress: internalSupernet
      type: 'AddressPrefix'
    }
    nextHop: {
      nextHopType: 'VirtualAppliance'
      nextHopAddress: firewallPrivateIpAddress
    }
  }
}

@description('3. Security Admin Configuration (Baseline Governance).')
resource secConfig 'Microsoft.Network/networkManagers/securityAdminConfigurations@2024-07-01' = {
  parent: avnm
  name: securityAdminConfigName
  dependsOn: [
    avnm
  ]
  properties: {
    description: 'Enforces global security rules that override NSGs.'
    applyOnNetworkIntentPolicyBasedServices: []
  }
}

@description('3a. Define the Security Rule Collection.')
resource secRuleCollection 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2024-07-01' = {
  parent: secConfig
  name: securityAdminRuleCollectionName
  properties: {
    appliesToGroups: [
      {
        networkGroupId: spokesNetworkGroupId
      }
    ]
  }
}

@description('3b. Example Rule: Deny RDP from Internet to all spokes.')
resource secRuleDenyRDP 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: secRuleCollection
  name: 'deny-rdp-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny RDP from Internet to all spokes'
    priority: 100
    protocol: 'Tcp'
    access: 'Deny'
    direction: 'Inbound'
    sources: [
      {
        addressPrefix: 'Internet'
        addressPrefixType: 'ServiceTag'
      }
    ]
    sourcePortRanges: [
      '0-65535'
    ]
    destinations: [
      {
        addressPrefix: '*'
        addressPrefixType: 'IPPrefix'
      }
    ]
    destinationPortRanges: [
      '3389'
    ]
  }
}

@description('3c. Deny SSH (22/TCP) from Internet to all spokes.')
resource secRuleDenySSH 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: secRuleCollection
  name: 'deny-ssh-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny SSH from Internet to all spokes'
    priority: 101
    protocol: 'Tcp'
    access: 'Deny'
    direction: 'Inbound'
    sources: [ { addressPrefix: 'Internet', addressPrefixType: 'ServiceTag' } ]
    sourcePortRanges: [ '0-65535' ]
    destinations: [ { addressPrefix: '*', addressPrefixType: 'IPPrefix' } ]
    destinationPortRanges: [ '22' ]
  }
}

@description('3d. Deny SMB (445/TCP) from Internet to all spokes.')
resource secRuleDenySMB 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: secRuleCollection
  name: 'deny-smb-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny SMB from Internet to all spokes'
    priority: 102
    protocol: 'Tcp'
    access: 'Deny'
    direction: 'Inbound'
    sources: [ { addressPrefix: 'Internet', addressPrefixType: 'ServiceTag' } ]
    sourcePortRanges: [ '0-65535' ]
    destinations: [ { addressPrefix: '*', addressPrefixType: 'IPPrefix' } ]
    destinationPortRanges: [ '445' ]
  }
}

@description('3e. Deny WinRM (5985/5986 TCP) from Internet to all spokes.')
resource secRuleDenyWinRM 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: secRuleCollection
  name: 'deny-winrm-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny WinRM from Internet to all spokes'
    priority: 103
    protocol: 'Tcp'
    access: 'Deny'
    direction: 'Inbound'
    sources: [ { addressPrefix: 'Internet', addressPrefixType: 'ServiceTag' } ]
    sourcePortRanges: [ '0-65535' ]
    destinations: [ { addressPrefix: '*', addressPrefixType: 'IPPrefix' } ]
    destinationPortRanges: [ '5985', '5986' ]
  }
}

// === OUTPUTS ===
@description('Security Admin Configuration ID.')
output securityAdminConfigId string = secConfig.id

@description('Security Admin Rule Collection ID.')
output securityAdminRuleCollectionId string = secRuleCollection.id

@description('Security Admin Rule ID (example: deny RDP).')
output securityAdminRuleId string = secRuleDenyRDP.id