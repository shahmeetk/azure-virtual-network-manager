// Azure Disaster Recovery Configuration Module
// This module configures disaster recovery for critical infrastructure components

@description('Location for primary resources')
param location string = resourceGroup().location

@description('Location for disaster recovery resources')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westus3'
  'centralus'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'southeastasia'
  'eastasia'
  'australiaeast'
  'australiasoutheast'
])
param drLocation string

@description('Resource name prefix')
@minLength(2)
@maxLength(10)
param prefix string

@description('Recovery Services Vault name for Site Recovery')
param siteRecoveryVaultName string = '${prefix}-asr-${uniqueString(resourceGroup().id)}'

@description('Primary VNet name for disaster recovery')
param primaryVnetName string

@description('DR VNet address prefix')
param drVnetAddressPrefix string

@description('Primary firewall name')
param primaryFirewallName string

@description('DR firewall name')
param drFirewallName string

@description('Resource tags')
param tags object = {}

@description('Enable automated failover')
param enableAutomatedFailover bool = false

@description('Enable network mapping for Site Recovery')
param enableNetworkMapping bool = true

@description('RPO threshold in minutes for alerts')
@minValue(5)
@maxValue(1440)
param rpoThresholdMinutes int = 60

@description('Alert threshold for test failover')
param testFailoverAlertThreshold int = 5

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string = ''

@description('Enable cross-region replication for AVNM')
param enableCrossRegionReplication bool = true

@description('AVNM resource name for disaster recovery')
param avnmName string

// Site Recovery Vault
resource siteRecoveryVault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: siteRecoveryVaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Site Recovery fabric for primary region
resource primaryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2023-04-01' = {
  parent: siteRecoveryVault
  name: '${prefix}-primary-fabric'
  location: location
  properties: {
    customDetails: {
      instanceType: 'VMwareV2'
      migrationRecoveryFabricId: resourceId('Microsoft.Network/networkManagers', avnmName)
    }
  }
}

// Site Recovery fabric for DR region
resource drFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2023-04-01' = {
  parent: siteRecoveryVault
  name: '${prefix}-dr-fabric'
  location: drLocation
  properties: {
    customDetails: {
      instanceType: 'Azure'
    }
  }
}

// DR VNet for disaster recovery site
resource drVnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: '${prefix}-dr-vnet'
  location: drLocation
  tags: union(tags, { 'Purpose': 'DisasterRecovery', 'PrimaryVnet': primaryVnetName })
  properties: {
    addressSpace: {
      addressPrefixes: [
        drVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: cidrSubnet(drVnetAddressPrefix, 24, 0)
          networkSecurityGroup: {
            id: resourceId('Microsoft.Network/networkSecurityGroups', '${prefix}-dr-nsg')
          }
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: cidrSubnet(drVnetAddressPrefix, 24, 1)
        }
      }
    ]
  }
}

// DR Network Security Group
resource drNsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${prefix}-dr-nsg'
  location: drLocation
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyInternetInbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// DR Firewall
resource drFirewall 'Microsoft.Network/azureFirewalls@2023-04-01' = {
  name: drFirewallName
  location: drLocation
  tags: union(tags, { 'Purpose': 'DisasterRecovery', 'PrimaryFirewall': primaryFirewallName })
  zones: length(string(location)) >= 2 ? pickZones('Microsoft.Network', 'azureFirewalls', drLocation, 3) : []
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: '${drVnet.id}/subnets/AzureFirewallSubnet'
          }
          publicIPAddress: {
            id: drFirewallPublicIP.id
          }
        }
      }
    ]
  }
  dependsOn: [
    drVnet
  ]
}

// DR Firewall Public IP
resource drFirewallPublicIP 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${drFirewallName}-pip'
  location: drLocation
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: length(string(location)) >= 2 ? pickZones('Microsoft.Network', 'publicIPAddresses', drLocation, 3) : []
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Site Recovery protection container for primary region
resource primaryProtectionContainer 'Microsoft.RecoveryServices/vaults/replicationFabrics/protectionContainers@2023-04-01' = {
  parent: primaryFabric
  name: '${prefix}-primary-container'
  properties: {
    providerSpecificInput: {
      instanceType: 'ReplicationProviderContainerUnprotectedInput'
    }
  }
}

// Site Recovery protection container for DR region
resource drProtectionContainer 'Microsoft.RecoveryServices/vaults/replicationFabrics/protectionContainers@2023-04-01' = {
  parent: drFabric
  name: '${prefix}-dr-container'
  properties: {
    providerSpecificInput: {
      instanceType: 'ReplicationProviderContainerUnprotectedInput'
    }
  }
}

// Network mapping for Site Recovery
resource networkMapping 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationNetworks/networkMappings@2023-04-01' = if (enableNetworkMapping) {
  name: '${prefix}-network-mapping'
  parent: primaryFabric
  properties: {
    fabricSpecificDetails: {
      instanceType: 'AzureToAzureNetworkMappingInput'
      primaryNetworkId: resourceId('Microsoft.Network/virtualNetworks', primaryVnetName)
      recoveryNetworkId: drVnet.id
    }
  }
}

// Site Recovery policy for disaster recovery
resource drPolicy 'Microsoft.RecoveryServices/vaults/replicationPolicies@2023-04-01' = {
  parent: siteRecoveryVault
  name: '${prefix}-dr-policy'
  properties: {
    providerSpecificInput: {
      instanceType: 'A2APolicyCreationInput'
      recoveryPointRetentionHours: 24
      appConsistentFrequencyHours: 1
      crashConsistentFrequencyMinutes: 5
      multiVmSyncStatus: 'Enabled'
    }
  }
}

// Recovery plan for automated failover
resource recoveryPlan 'Microsoft.RecoveryServices/vaults/replicationRecoveryPlans@2023-04-01' = {
  parent: siteRecoveryVault
  name: '${prefix}-recovery-plan'
  properties: {
    primaryFabricId: primaryFabric.id
    recoveryFabricId: drFabric.id
    failoverDeploymentModel: 'ResourceManager'
    groups: [
      {
        groupType: 'Shutdown'
        replicationProtectedItems: []
        startGroupActions: []
        endGroupActions: []
      }
      {
        groupType: 'Failover'
        replicationProtectedItems: []
        startGroupActions: []
        endGroupActions: []
      }
      {
        groupType: 'Boot'
        replicationProtectedItems: []
        startGroupActions: []
        endGroupActions: []
      }
    ]
    allowedOperations: [
      'TestFailover'
      'UnplannedFailover'
      'PlannedFailover'
    ]
  }
}

// Diagnostic settings for Site Recovery vault
resource siteRecoveryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${siteRecoveryVaultName}-diagnostics'
  scope: siteRecoveryVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AzureSiteRecoveryJobs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AzureSiteRecoveryEvents'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AzureSiteRecoveryReplicatedItems'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AzureSiteRecoveryReplicationStats'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

// Alert rules for Site Recovery
resource rpoAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${prefix}-rpo-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when RPO exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      siteRecoveryVault.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          threshold: rpoThresholdMinutes
          name: 'RPO Threshold'
          metricName: 'RPO'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: resourceId('Microsoft.Insights/actionGroups', '${prefix}-dr-action-group')
      }
    ]
  }
}

// Action group for disaster recovery alerts
resource drActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${prefix}-dr-action-group'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: '${prefix}DRAG'
    enabled: true
    emailReceivers: [
      {
        name: 'DRAdmin'
        emailAddress: 'admin@contoso.com'
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// Cross-region replication for AVNM
resource avnmCrossRegionConfig 'Microsoft.Network/networkManagers@2023-04-01' = if (enableCrossRegionReplication) {
  name: '${avnmName}-dr'
  location: drLocation
  tags: union(tags, { 'Purpose': 'DisasterRecovery', 'PrimaryAvnm': avnmName })
  properties: {
    networkManagerScopeAccesses: [
      'Connectivity'
      'SecurityAdmin'
    ]
    networkManagerScopes: {
      subscriptions: [
        subscription().id
      ]
    }
    description: 'Disaster Recovery Network Manager for ${avnmName}'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Outputs
output drVnetName string = drVnet.name
output drVnetId string = drVnet.id
output drFirewallName string = drFirewall.name
output drFirewallId string = drFirewall.id
output siteRecoveryVaultName string = siteRecoveryVault.name
output siteRecoveryVaultId string = siteRecoveryVault.id
output recoveryPlanName string = recoveryPlan.name
output recoveryPlanId string = recoveryPlan.id
output drLocation string = drLocation
output drResourceGroup string = resourceGroup().name