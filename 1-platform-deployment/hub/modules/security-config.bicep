/*
  ====================================================================
  MODULE:   security-config.bicep
  SCOPE:    Resource Group
  DESC:     Deploys security configurations including RBAC roles,
            network security groups, and diagnostic settings.
  ====================================================================
*/

targetScope = 'resourceGroup'

// === PARAMETERS ===
@description('The Azure region for all resources.')
param location string

@description('A short, unique prefix for naming all resources.')
param prefix string

@description('The name of the AVNM instance.')
param avnmName string

@description('The name of the IPAM Pool.')
param ipamPoolName string

@description('Array of principal IDs that should have Network Contributor access.')
param networkContributorPrincipalIds array = []

@description('Array of principal IDs that should have Reader access.')
param readerPrincipalIds array = []

@description('Log Analytics workspace ID for diagnostics.')
param logAnalyticsWorkspaceId string = ''

// === VARIABLES ===
var networkContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98e-9d83-4d0b-9f80-7d1d24b0c6b5')
var readerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')

// === EXISTING RESOURCES ===
resource avnm 'Microsoft.Network/networkManagers@2023-11-01' existing = {
  name: avnmName
}

resource ipamPool 'Microsoft.Network/networkManagers/ipamPools@2023-11-01' existing = {
  parent: avnm
  name: ipamPoolName
}

// === RESOURCES ===

@description('1. Assign Network Contributor role to specified principals for AVNM.')
resource avnmNetworkContributorRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in networkContributorPrincipalIds: {
  name: guid(avnm.id, principalId, networkContributorRoleDefinitionId)
  scope: avnm
  properties: {
    roleDefinitionId: networkContributorRoleDefinitionId
    principalId: principalId
    principalType: 'User' // Can be 'User', 'Group', or 'ServicePrincipal'
  }
}]

@description('2. Assign Reader role to specified principals for AVNM.')
resource avnmReaderRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in readerPrincipalIds: {
  name: guid(avnm.id, principalId, readerRoleDefinitionId)
  scope: avnm
  properties: {
    roleDefinitionId: readerRoleDefinitionId
    principalId: principalId
    principalType: 'User'
  }
}]

@description('3. Assign Network Contributor role to specified principals for IPAM Pool.')
resource ipamNetworkContributorRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in networkContributorPrincipalIds: {
  name: guid(ipamPool.id, principalId, networkContributorRoleDefinitionId)
  scope: ipamPool
  properties: {
    roleDefinitionId: networkContributorRoleDefinitionId
    principalId: principalId
    principalType: 'User'
  }
}]

@description('4. Network Security Group for AVNM resources.')
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${prefix}-avnm-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyInternetInbound'
        properties: {
          description: 'Deny all inbound traffic from Internet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          description: 'Allow Azure Load Balancer health probes'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
    ]
  }
}

@description('5. Diagnostic settings for AVNM.')
resource avnmDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${prefix}-avnm-diagnostics'
  scope: avnm
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'NetworkManagerConnectivityConfiguration'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'NetworkManagerSecurityAdminConfiguration'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'NetworkManagerRoutingConfiguration'
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

@description('6. Enable encryption at rest for AVNM.')
resource avnmEncryption 'Microsoft.Network/networkManagers@2023-11-01' = {
  name: avnmName
  location: location
  properties: {
    encryption: {
      encryptionType: 'UserAssigned'
      userAssignedIdentity: {
        // Using system-assigned managed identity for encryption
        identityType: 'SystemAssigned'
      }
    }
  }
  dependsOn: [
    avnmNetworkContributorRoleAssignments
    avnmReaderRoleAssignments
  ]
}

// === OUTPUTS ===
@description('The ID of the Network Security Group.')
output nsgId string = !empty(logAnalyticsWorkspaceId) ? nsg.id : ''

@description('The ID of the diagnostic settings.')
output diagnosticsId string = !empty(logAnalyticsWorkspaceId) ? avnmDiagnostics.id : ''