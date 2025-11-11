/*
  ====================================================================
  MODULE:   avnm-configs-min.bicep
  STATUS:   DEPRECATED (Do not use)
  --------------------------------------------------------------------
  This minimal module has been superseded by modules/avnm-configs.bicep,
  which now contains the complete, production-ready configuration for:
    - Connectivity (Hub-and-Spoke)
    - Routing (force spoke traffic via hub firewall when provided)
    - Security Admin (baseline governance rules)

  The hub deployment (1-platform-deployment/hub/main.bicep) is already
  wired to use modules/avnm-configs.bicep. This file is retained only
  temporarily for backward compatibility and will be removed.

  ACTION: Switch all usages to modules/avnm-configs.bicep.
  ====================================================================
*/

targetScope = 'resourceGroup'

// === PARAMETERS ===
@description('The name of the AVNM instance (from avnm-core.bicep).')
param avnmName string

@description('The Resource ID of the Spokes Network Group. Rules will apply to this NG.')
param spokesNetworkGroupId string

@description('The full Resource ID of the Hub VNet (needed for connectivity auto-probe).')
param hubVnetId string

@description('Toggle to deploy security admin configuration.')
param deploySecurity bool = true

@description('Optional: Hub firewall private IP to force-route traffic through. When empty, routing is skipped.')
param firewallPrivateIpAddress string = ''

@description('Optional: Internal supernet (e.g., IPAM pool) for spoke-to-spoke traffic. When provided with firewall IP, spoke-to-spoke is forced via firewall.')
param internalSupernet string = ''

var enableRouting = !empty(firewallPrivateIpAddress) && !empty(internalSupernet)

// === EXISTING RESOURCES ===
@description('Reference to the parent AVNM resource.')
resource avnm 'Microsoft.Network/networkManagers@2024-10-01' existing = {
  name: avnmName
}

// === RESOURCES ===
@description('Security Admin Configuration (Baseline Governance).')
resource secConfig 'Microsoft.Network/networkManagers/securityAdminConfigurations@2024-10-01' = if (deploySecurity) {
  parent: avnm
  name: 'sac-global-baseline'
  dependsOn: [ avnm ]
  properties: {
    description: 'Baseline security admin configuration.'
    applyOnNetworkIntentPolicyBasedServices: []
  }
}

@description('Security Rule Collection attached to the baseline config.')
resource secRuleCollection 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2024-10-01' = if (deploySecurity) {
  parent: secConfig
  name: 'sc-baseline-rules'
  dependsOn: [ secConfig ]
  properties: {
    appliesToGroups: [
      {
        networkGroupId: spokesNetworkGroupId
      }
    ]
    description: 'Baseline deny/allow rules for spokes.'
  }
}

@description('Example Rule: Deny RDP from Internet to all spokes.')
resource secRuleDenyRDP 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-10-01' = if (deploySecurity) {
  parent: secRuleCollection
  name: 'deny-rdp-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny RDP from Internet to all spokes.'
    priority: 100
    protocol: 'Tcp'
    access: 'Deny'
    direction: 'Inbound'
    sources: [ { addressPrefix: 'Internet', addressPrefixType: 'ServiceTag' } ]
    sourcePortRanges: [ '0-65535' ]
    destinations: [ { addressPrefix: '*', addressPrefixType: 'IPPrefix' } ]
    destinationPortRanges: [ '3389' ]
  }
}

@description('Deny SSH from Internet to all spokes.')
resource secRuleDenySSH 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-10-01' = if (deploySecurity) {
  parent: secRuleCollection
  name: 'deny-ssh-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny SSH (22/TCP) from Internet to all spokes.'
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

@description('Deny SMB from Internet to all spokes.')
resource secRuleDenySMB 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-10-01' = if (deploySecurity) {
  parent: secRuleCollection
  name: 'deny-smb-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny SMB (445/TCP) from Internet to all spokes.'
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

@description('Deny WinRM from Internet to all spokes.')
resource secRuleDenyWinRM 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-10-01' = if (deploySecurity) {
  parent: secRuleCollection
  name: 'deny-winrm-from-internet'
  kind: 'Custom'
  properties: {
    description: 'Deny WinRM (5985/5986 TCP) from Internet to all spokes.'
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

@description('Routing Configuration: force spoke-to-spoke and Internet traffic via hub firewall (when parameters provided).')
resource routeConfig 'Microsoft.Network/networkManagers/routingConfigurations@2024-10-01' = if (enableRouting) {
  parent: avnm
  name: 'rc-force-traffic-to-firewall'
  properties: {
    description: 'Force all spoke traffic (Internet and internal) to the hub firewall.'
    appliesToGroups: [ { networkGroupId: spokesNetworkGroupId } ]
  }
}

@description('Routing rule collection applied to spokes.')
resource routeRuleCollection 'Microsoft.Network/networkManagers/routingConfigurations/ruleCollections@2024-10-01' = if (enableRouting) {
  parent: routeConfig
  name: 'rc-collection-default'
  properties: {
    appliesToGroups: [ { networkGroupId: spokesNetworkGroupId } ]
  }
}

@description('Internet-bound traffic to firewall (0.0.0.0/0).')
resource routeRuleInternet 'Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-10-01' = if (enableRouting) {
  parent: routeRuleCollection
  name: 'rule-internet-to-firewall'
  kind: 'Custom'
  properties: {
    description: 'Route Internet traffic to Virtual Appliance in Hub.'
    destinations: [ { addressPrefix: '0.0.0.0/0', addressPrefixType: 'IPPrefix' } ]
    nextHopType: 'VirtualAppliance'
    nextHop: firewallPrivateIpAddress
  }
}

@description('Internal supernet (spoke-to-spoke) to firewall.')
resource routeRuleInternal 'Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-10-01' = if (enableRouting) {
  parent: routeRuleCollection
  name: 'rule-internal-to-firewall'
  kind: 'Custom'
  properties: {
    description: 'Route internal supernet to Virtual Appliance in Hub.'
    destinations: [ { addressPrefix: internalSupernet, addressPrefixType: 'IPPrefix' } ]
    nextHopType: 'VirtualAppliance'
    nextHop: firewallPrivateIpAddress
  }
}

// === OUTPUTS ===
@description('Security Admin Configuration ID (if deployed).')
output securityAdminConfigId string = deploySecurity ? secConfig.id : ''

@description('Security Admin Rule Collection ID (if deployed).')
output securityAdminRuleCollectionId string = deploySecurity ? secRuleCollection.id : ''

@description('Security Admin Rule ID (if deployed).')
output securityAdminRuleId string = deploySecurity ? secRuleDenyRDP.id : ''
