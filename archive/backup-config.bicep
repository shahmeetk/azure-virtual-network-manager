// Azure Backup and Disaster Recovery Configuration Module
// This module configures backup and disaster recovery for critical infrastructure components

@description('Location for all resources')
param location string = resourceGroup().location

@description('Resource name prefix')
@minLength(2)
@maxLength(10)
param prefix string

@description('Recovery Services Vault name')
param vaultName string = '${prefix}-rsv-${uniqueString(resourceGroup().id)}'

@description('Backup policy name for daily backups')
param dailyBackupPolicyName string = '${prefix}-daily-policy'

@description('Backup policy name for weekly backups')
param weeklyBackupPolicyName string = '${prefix}-weekly-policy'

@description('Resource tags')
param tags object = {}

@description('Enable cross-region restore')
param enableCrossRegionRestore bool = true

@description('Enable soft delete for backup items')
param enableSoftDelete bool = true

@description('Soft delete retention period in days')
@minValue(7)
@maxValue(365)
param softDeleteRetentionDays int = 14

@description('Enable alerts for backup failures')
param enableBackupAlerts bool = true

@description('Alert email addresses for backup notifications')
param alertEmailAddresses array = []

@description('AVNM resource name for backup configuration')
param avnmName string

@description('Log Analytics workspace ID for backup monitoring')
param logAnalyticsWorkspaceId string = ''

@description('Enable geo-redundant backup storage')
param enableGeoRedundantStorage bool = true

// Recovery Services Vault
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    restoreSettings: {
      crossRegionRestore: enableCrossRegionRestore ? 'Enabled' : 'Disabled'
    }
    securitySettings: {
      immutabilitySettings: {
        state: 'Unlocked'
      }
      softDeleteSettings: {
        softDeleteRetentionPeriodInDays: enableSoftDelete ? softDeleteRetentionDays : 0
        softDeleteState: enableSoftDelete ? 'Enabled' : 'Disabled'
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Daily backup policy
resource dailyBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: recoveryServicesVault
  name: dailyBackupPolicyName
  properties: {
    backupManagementType: 'AzureIaasVM'
    instantRPDetails: {}
    instantRpRetentionRangeInDays: 5
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2023-01-01T02:00:00Z'
      ]
      scheduleWeeklyFrequency: 0
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2023-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
    }
    timeZone: 'UTC'
  }
}

// Weekly backup policy
resource weeklyBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: recoveryServicesVault
  name: weeklyBackupPolicyName
  properties: {
    backupManagementType: 'AzureIaasVM'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Weekly'
      scheduleRunTimes: [
        '2023-01-01T03:00:00Z'
      ]
      scheduleRunDays: [
        'Sunday'
      ]
      scheduleWeeklyFrequency: 0
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      weeklySchedule: {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          '2023-01-01T03:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Weeks'
        }
      }
    }
    timeZone: 'UTC'
  }
}

// Backup alert configuration
resource backupAlerts 'Microsoft.RecoveryServices/vaults/monitoringConfigurations/notificationConfiguration@2023-04-01' = if (enableBackupAlerts && length(alertEmailAddresses) > 0) {
  parent: recoveryServicesVault
  name: 'default'
  properties: {
    alerts: [
      {
        alertType: 'JobFailure'
        notificationType: 'Email'
        isEnabled: true
      }
      {
        alertType: 'ImmediateHealthStatus'
        notificationType: 'Email'
        isEnabled: true
      }
      {
        alertType: 'ScheduledBackupStatus'
        notificationType: 'Email'
        isEnabled: true
      }
    ]
    notificationSettings: {
      notificationType: 'Email'
      emailAddresses: alertEmailAddresses
      emailSubscriptions: []
    }
  }
}

// Diagnostic settings for backup vault
resource backupVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${vaultName}-diagnostics'
  scope: recoveryServicesVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AzureBackupReport'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'CoreAzureBackup'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AddonAzureBackupAlerts'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AddonAzureBackupJobs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AddonAzureBackupPolicy'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AddonAzureBackupProtectedInstance'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AddonAzureBackupStorage'
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

// Role assignment for backup vault access
resource backupContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(recoveryServicesVault.id, 'backup-contributor')
  scope: recoveryServicesVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e467623-bb1f-42f4-a55d-6e525e11383b') // Backup Contributor
    principalId: recoveryServicesVault.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Backup configuration for AVNM (example for protecting critical network configurations)
resource avnmBackupConfiguration 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-04-01' = {
  parent: recoveryServicesVault
  name: 'Azure/${avnmName}/azurestoragecontainer;${avnmName};AzureVMBackup'
  properties: {
    protectedItemType: 'AzureVmWorkloadSAPAseDatabase'
    backupManagementType: 'AzureIaasVM'
    workloadType: 'AzureVmWorkloadSAPAseDatabase'
    policyId: dailyBackupPolicy.id
    sourceResourceId: resourceId('Microsoft.Network/networkManagers', avnmName)
  }
}

// Outputs
output vaultName string = recoveryServicesVault.name
output vaultId string = recoveryServicesVault.id
output dailyBackupPolicyId string = dailyBackupPolicy.id
output weeklyBackupPolicyId string = weeklyBackupPolicy.id
output backupResourceGroup string = resourceGroup().name
output vaultIdentityPrincipalId string = recoveryServicesVault.identity.principalId