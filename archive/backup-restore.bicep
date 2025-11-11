// Azure Backup and Restore Operations Module
// This module provides backup and restore capabilities for critical infrastructure

@description('Location for all resources')
param location string = resourceGroup().location

@description('Resource name prefix')
@minLength(2)
@maxLength(10)
param prefix string

@description('Recovery Services Vault name')
param vaultName string = '${prefix}-rsv-${uniqueString(resourceGroup().id)}'

@description('Backup policy name')
param backupPolicyName string = '${prefix}-backup-policy'

@description('Resource tags')
param tags object = {}

@description('Items to backup')
param backupItems array = []

@description('Backup schedule configuration')
param backupSchedule object = {
  frequency: 'Daily'
  time: '02:00'
  timezone: 'UTC'
}

@description('Retention policy configuration')
param retentionPolicy object = {
  daily: {
    count: 30
    durationType: 'Days'
  }
  weekly: {
    count: 12
    durationType: 'Weeks'
  }
  monthly: {
    count: 12
    durationType: 'Months'
  }
  yearly: {
    count: 3
    durationType: 'Years'
  }
}

@description('Enable backup encryption')
param enableEncryption bool = true

@description('Encryption key URL from Key Vault')
param encryptionKeyUrl string = ''

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string = ''

@description('Enable backup alerts')
param enableAlerts bool = true

@description('Alert email addresses')
param alertEmailAddresses array = []

@description('AVNM resource name for backup')
param avnmName string

@description('IPAM Pool name for backup')
param ipamPoolName string

@description('Enable point-in-time restore')
param enablePointInTimeRestore bool = true

@description('Point-in-time restore retention in hours')
@minValue(1)
@maxValue(168)
param pitrRetentionHours int = 24

// Recovery Services Vault (if not exists)
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
      crossRegionRestore: 'Enabled'
    }
    securitySettings: {
      immutabilitySettings: {
        state: 'Unlocked'
      }
      softDeleteSettings: {
        softDeleteRetentionPeriodInDays: 14
        softDeleteState: 'Enabled'
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Backup policy with custom retention
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: recoveryServicesVault
  name: backupPolicyName
  properties: {
    backupManagementType: 'AzureIaasVM'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: backupSchedule.frequency
      scheduleRunTimes: [
        '2023-01-01T${backupSchedule.time}:00Z'
      ]
      scheduleWeeklyFrequency: 0
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: retentionPolicy.daily.count > 0 ? {
        retentionTimes: [
          '2023-01-01T${backupSchedule.time}:00Z'
        ]
        retentionDuration: {
          count: retentionPolicy.daily.count
          durationType: retentionPolicy.daily.durationType
        }
      } : null
      weeklySchedule: retentionPolicy.weekly.count > 0 ? {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          '2023-01-01T${backupSchedule.time}:00Z'
        ]
        retentionDuration: {
          count: retentionPolicy.weekly.count
          durationType: retentionPolicy.weekly.durationType
        }
      } : null
      monthlySchedule: retentionPolicy.monthly.count > 0 ? {
        retentionScheduleFormatType: 'Weekly'
        retentionScheduleWeekly: {
          daysOfTheWeek: [
            'Sunday'
          ]
          weeksOfTheMonth: [
            'First'
          ]
        }
        retentionTimes: [
          '2023-01-01T${backupSchedule.time}:00Z'
        ]
        retentionDuration: {
          count: retentionPolicy.monthly.count
          durationType: retentionPolicy.monthly.durationType
        }
      } : null
      yearlySchedule: retentionPolicy.yearly.count > 0 ? {
        retentionScheduleFormatType: 'Weekly'
        monthsOfYear: [
          'January'
        ]
        retentionScheduleWeekly: {
          daysOfTheWeek: [
            'Sunday'
          ]
          weeksOfTheMonth: [
            'First'
          ]
        }
        retentionTimes: [
          '2023-01-01T${backupSchedule.time}:00Z'
        ]
        retentionDuration: {
          count: retentionPolicy.yearly.count
          durationType: retentionPolicy.yearly.durationType
        }
      } : null
    }
    instantRPDetails: {}
    instantRpRetentionRangeInDays: enablePointInTimeRestore ? pitrRetentionHours / 24 : 5
  }
}

// Backup encryption configuration
resource backupEncryption 'Microsoft.RecoveryServices/vaults/backupEncryptionConfigs@2023-04-01' = if (enableEncryption && !empty(encryptionKeyUrl)) {
  parent: recoveryServicesVault
  name: 'default'
  properties: {
    encryptionAtRestType: 'CustomerManaged'
    keyUri: encryptionKeyUrl
    infrastructureEncryptionState: 'Enabled'
  }
}

// Backup configuration for AVNM
resource avnmBackup 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-04-01' = {
  parent: recoveryServicesVault
  name: 'Azure/${avnmName}/azurestoragecontainer;${avnmName};AzureVMBackup'
  properties: {
    protectedItemType: 'AzureVmWorkloadSAPAseDatabase'
    backupManagementType: 'AzureIaasVM'
    workloadType: 'AzureVmWorkloadSAPAseDatabase'
    policyId: backupPolicy.id
    sourceResourceId: resourceId('Microsoft.Network/networkManagers', avnmName)
    isScheduledForBackup: true
    lastBackupStatus: 'Completed'
    lastBackupTime: '2023-01-01T00:00:00Z'
    backupSetName: '${avnmName}-backup-set'
  }
}

// Backup configuration for IPAM Pool
resource ipamPoolBackup 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-04-01' = {
  parent: recoveryServicesVault
  name: 'Azure/${ipamPoolName}/azurestoragecontainer;${ipamPoolName};AzureVMBackup'
  properties: {
    protectedItemType: 'AzureVmWorkloadSAPAseDatabase'
    backupManagementType: 'AzureIaasVM'
    workloadType: 'AzureVmWorkloadSAPAseDatabase'
    policyId: backupPolicy.id
    sourceResourceId: resourceId('Microsoft.Network/networkManagers/ipamPools', avnmName, ipamPoolName)
    isScheduledForBackup: true
    lastBackupStatus: 'Completed'
    lastBackupTime: '2023-01-01T00:00:00Z'
    backupSetName: '${ipamPoolName}-backup-set'
  }
}

// Backup alerts configuration
resource backupAlerts 'Microsoft.RecoveryServices/vaults/monitoringConfigurations/notificationConfiguration@2023-04-01' = if (enableAlerts && length(alertEmailAddresses) > 0) {
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
      {
        alertType: 'CriticalHealthStatus'
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

// Diagnostic settings for backup monitoring
resource backupDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
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

// Backup health monitoring alert
resource backupHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerts) {
  name: '${vaultName}-health-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when backup health is degraded'
    severity: 2
    enabled: true
    scopes: [
      recoveryServicesVault.id
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          threshold: 0
          name: 'Backup Health'
          metricName: 'BackupHealthEvent'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: resourceId('Microsoft.Insights/actionGroups', '${prefix}-backup-action-group')
      }
    ]
  }
}

// Action group for backup alerts
resource backupActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerts && length(alertEmailAddresses) > 0) {
  name: '${prefix}-backup-action-group'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: '${prefix}BKPAG'
    enabled: true
    emailReceivers: [for email in alertEmailAddresses: {
      name: 'BackupAdmin-${uniqueString(email)}'
      emailAddress: email
    }]
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

// Backup compliance monitoring
resource backupCompliance 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: recoveryServicesVault
  name: '${prefix}-compliance-policy'
  properties: {
    backupManagementType: 'AzureIaasVM'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2023-01-01T01:00:00Z'
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2023-01-01T01:00:00Z'
        ]
        retentionDuration: {
          count: 7
          durationType: 'Days'
        }
      }
    }
  }
}

// Outputs
output vaultName string = recoveryServicesVault.name
output vaultId string = recoveryServicesVault.id
output backupPolicyId string = backupPolicy.id
output backupPolicyName string = backupPolicy.name
output vaultIdentityPrincipalId string = recoveryServicesVault.identity.principalId
output encryptionEnabled bool = enableEncryption && !empty(encryptionKeyUrl)
output pointInTimeRestoreEnabled bool = enablePointInTimeRestore