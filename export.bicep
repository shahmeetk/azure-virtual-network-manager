param networkManagers_test_avnm_name string = 'test-avnm'
param virtualNetworks_spoke_dev_001_name string = 'spoke-dev-001'
param virtualNetworks_spoke_dev_002_name string = 'spoke-dev-002'
param virtualNetworks_aznm_test_vnet_name string = 'aznm-test-vnet'

resource networkManagers_test_avnm_name_resource 'Microsoft.Network/networkManagers@2024-07-01' = {
  name: networkManagers_test_avnm_name
  location: 'eastus'
  properties: {
    description: 'Central AVNM for enterprise connectivity and security.'
    networkManagerScopes: {
      managementGroups: []
      subscriptions: [
        '/subscriptions/b572f84c-ea09-465a-a35b-b4b1ee9a7152'
      ]
    }
    networkManagerScopeAccesses: [
      'Connectivity'
      'SecurityAdmin'
    ]
  }
}

resource virtualNetworks_aznm_test_vnet_name_resource 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: virtualNetworks_aznm_test_vnet_name
  location: 'eastus'
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    privateEndpointVNetPolicies: 'Disabled'
    subnets: []
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

resource networkManagers_test_avnm_name_test_ipam_pool 'Microsoft.Network/networkManagers/ipamPools@2024-07-01' = {
  parent: networkManagers_test_avnm_name_resource
  name: 'test-ipam-pool'
  location: 'eastus'
  properties: {
    description: 'Global IPAM pool for all spokes.'
    addressPrefixes: [
      '10.0.0.0/17'
    ]
    provisioningState: 'Succeeded'
  }
}

resource networkManagers_test_avnm_name_test_ng_hub_static 'Microsoft.Network/networkManagers/networkGroups@2024-07-01' = {
  parent: networkManagers_test_avnm_name_resource
  name: 'test-ng-hub-static'
  properties: {
    description: 'Static group containing the Hub VNet.'
    memberType: 'VirtualNetwork'
  }
}

resource networkManagers_test_avnm_name_test_ng_spokes_dynamic 'Microsoft.Network/networkManagers/networkGroups@2024-07-01' = {
  parent: networkManagers_test_avnm_name_resource
  name: 'test-ng-spokes-dynamic'
  properties: {
    description: 'Dynamic group for all tagged spoke VNets.'
    memberType: 'VirtualNetwork'
  }
}

resource networkManagers_test_avnm_name_sac_global_baseline 'Microsoft.Network/networkManagers/securityAdminConfigurations@2024-07-01' = {
  parent: networkManagers_test_avnm_name_resource
  name: 'sac-global-baseline'
  properties: {
    description: 'Enforces global security rules that override NSGs.'
    applyOnNetworkIntentPolicyBasedServices: []
    networkGroupAddressSpaceAggregationOption: 'None'
  }
}

resource virtualNetworks_spoke_dev_001_name_resource 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: virtualNetworks_spoke_dev_001_name
  location: 'eastus'
  tags: {
    'avnm-group': 'spokes'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/22'
      ]
      ipamPoolPrefixAllocations: [
        {
          numberOfIpAddresses: '1024'
          pool: {
            id: networkManagers_test_avnm_name_test_ipam_pool.id
          }
        }
      ]
    }
    privateEndpointVNetPolicies: 'Disabled'
    subnets: []
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

resource virtualNetworks_spoke_dev_002_name_resource 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: virtualNetworks_spoke_dev_002_name
  location: 'eastus'
  tags: {
    'avnm-group': 'spokes'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.4.0/22'
      ]
      ipamPoolPrefixAllocations: [
        {
          numberOfIpAddresses: '1024'
          pool: {
            id: networkManagers_test_avnm_name_test_ipam_pool.id
          }
        }
      ]
    }
    encryption: {
      enabled: false
      enforcement: 'AllowUnencrypted'
    }
    privateEndpointVNetPolicies: 'Disabled'
    subnets: [
      {
        name: 'default'
        id: virtualNetworks_spoke_dev_002_name_default.id
        properties: {
          addressPrefixes: [
            '10.0.4.0/24'
          ]
          ipamPoolPrefixAllocations: [
            {
              numberOfIpAddresses: '256'
              pool: {
                id: networkManagers_test_avnm_name_test_ipam_pool.id
              }
            }
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

resource virtualNetworks_spoke_dev_002_name_default 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${virtualNetworks_spoke_dev_002_name}/default'
  properties: {
    addressPrefixes: [
      '10.0.4.0/24'
    ]
    ipamPoolPrefixAllocations: [
      {
        numberOfIpAddresses: '256'
        pool: {
          id: networkManagers_test_avnm_name_test_ipam_pool.id
        }
      }
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [
    virtualNetworks_spoke_dev_002_name_resource
  ]
}

resource networkManagers_test_avnm_name_hub_and_spoke_connectivity 'Microsoft.Network/networkManagers/connectivityConfigurations@2024-07-01' = {
  parent: networkManagers_test_avnm_name_resource
  name: 'hub-and-spoke-connectivity'
  properties: {
    connectivityTopology: 'HubAndSpoke'
    hubs: [
      {
        resourceType: 'Microsoft.Network/virtualNetworks'
        resourceId: virtualNetworks_aznm_test_vnet_name_resource.id
      }
    ]
    appliesToGroups: [
      {
        networkGroupId: networkManagers_test_avnm_name_test_ng_spokes_dynamic.id
        groupConnectivity: 'None'
        useHubGateway: 'False'
        isGlobal: 'False'
      }
    ]
    deleteExistingPeering: 'True'
    isGlobal: 'False'
    connectivityCapabilities: {
      connectedGroupPrivateEndpointsScale: 'Standard'
      connectedGroupAddressOverlap: 'Allowed'
      peeringEnforcement: 'Unenforced'
    }
  }
}

resource networkManagers_test_avnm_name_test_ng_hub_static_hub_vnet_member 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-07-01' = {
  parent: networkManagers_test_avnm_name_test_ng_hub_static
  name: 'hub-vnet-member'
  properties: {
    resourceId: virtualNetworks_aznm_test_vnet_name_resource.id
  }
  dependsOn: [
    networkManagers_test_avnm_name_resource
  ]
}

resource networkManagers_test_avnm_name_test_ng_spokes_dynamic_spoke_dev_001_member 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-07-01' = {
  parent: networkManagers_test_avnm_name_test_ng_spokes_dynamic
  name: 'spoke-dev-001-member'
  properties: {
    resourceId: virtualNetworks_spoke_dev_001_name_resource.id
  }
  dependsOn: [
    networkManagers_test_avnm_name_resource
  ]
}

resource networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2024-07-01' = {
  parent: networkManagers_test_avnm_name_sac_global_baseline
  name: 'sc-baseline-rules'
  properties: {
    appliesToGroups: [
      {
        networkGroupId: networkManagers_test_avnm_name_test_ng_spokes_dynamic.id
      }
    ]
  }
  dependsOn: [
    networkManagers_test_avnm_name_resource
  ]
}

resource networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules_deny_rdp_from_internet 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules
  name: 'deny-rdp-from-internet'
  kind: 'Custom'
  dependsOn: [
    networkManagers_test_avnm_name_sac_global_baseline
    networkManagers_test_avnm_name_resource
  ]
}

resource networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules_deny_smb_from_internet 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules
  name: 'deny-smb-from-internet'
  kind: 'Custom'
  dependsOn: [
    networkManagers_test_avnm_name_sac_global_baseline
    networkManagers_test_avnm_name_resource
  ]
}

resource networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules_deny_ssh_from_internet 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules
  name: 'deny-ssh-from-internet'
  kind: 'Custom'
  dependsOn: [
    networkManagers_test_avnm_name_sac_global_baseline
    networkManagers_test_avnm_name_resource
  ]
}

resource networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules_deny_winrm_from_internet 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-07-01' = {
  parent: networkManagers_test_avnm_name_sac_global_baseline_sc_baseline_rules
  name: 'deny-winrm-from-internet'
  kind: 'Custom'
  dependsOn: [
    networkManagers_test_avnm_name_sac_global_baseline
    networkManagers_test_avnm_name_resource
  ]
}
