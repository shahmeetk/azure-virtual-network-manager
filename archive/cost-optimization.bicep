// == PURPOSE ==
// This module implements cost optimization features including auto-shutdown schedules,
// resource tagging for cost tracking, and budget alerts.
// == PARAMETERS ==
@description('The Azure region where cost optimization resources will be deployed.')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'centralus'
  'northeurope'
  'westeurope'
  'uksouth'
  'southeastasia'
])
param location string = resourceGroup().location

@description('Prefix for naming cost optimization resources.')
@minLength(3)
@maxLength(10)
@pattern('^[a-z][a-z0-9-]*[a-z0-9]$')
param prefix string

@description('Enable auto-shutdown for non-production resources.')
param enableAutoShutdown bool = true

@description('Auto-shutdown time in UTC (HH:MM format).')
@pattern('^([01]?[0-9]|2[0-3]):[0-5][0-9]$')
param autoShutdownTime string = '18:00'

@description('Auto-shutdown timezone.')
@allowed([
  'UTC'
  'Pacific Standard Time'
  'Mountain Standard Time'
  'Central Standard Time'
  'Eastern Standard Time'
  'GMT Standard Time'
  'Central European Time'
  'W. Europe Standard Time'
])
param autoShutdownTimezone string = 'UTC'

@description('Monthly budget amount in USD.')
@minValue(10)
@maxValue(100000)
param monthlyBudget int = 500

@description('Budget alert threshold percentages.')
param budgetAlertThresholds array = [50, 75, 90, 100]

@description('Contact email for budget alerts.')
param budgetAlertEmail string = ''

@description('Enable cost tracking tags.')
param enableCostTrackingTags bool = true

@description('Environment type for cost optimization.')
@allowed(['Development', 'Test', 'Staging', 'Production'])
param environmentType string = 'Development'

@description('Tags to apply to cost optimization resources.')
param tags object = {}

// == VARIABLES ==
var budgetName = '${prefix}-monthly-budget'
var autoShutdownName = '${prefix}-auto-shutdown'
var costTrackingTags = enableCostTrackingTags ? {
  'CostCenter': 'IT-Infrastructure'
  'Environment': environmentType
  'AutoShutdown': string(enableAutoShutdown)
  'BudgetLimit': string(monthlyBudget)
  'Owner': 'Platform-Team'
  'Chargeback': 'Shared-Services'
} : {}

// == RESOURCES ==
@description('Monthly budget for cost monitoring')
resource budget 'Microsoft.Consumption/budgets@2023-03-01' = {
  name: budgetName
  scope: resourceGroup()
  properties: {
    amount: monthlyBudget
    timeGrain: 'Monthly'
    category: 'Cost'
    timePeriod: {
      startDate: dateTimeAdd(utcNow('yyyy-MM-dd'), 'P1D')
      endDate: dateTimeAdd(utcNow('yyyy-MM-dd'), 'P1Y')
    }
    notifications: {
      '50-percent': {
        enabled: contains(budgetAlertThresholds, 50)
        operator: 'GreaterThan'
        threshold: 50
        contactEmails: !empty(budgetAlertEmail) ? [budgetAlertEmail] : []
        contactRoles: ['Owner', 'Contributor']
      }
      '75-percent': {
        enabled: contains(budgetAlertThresholds, 75)
        operator: 'GreaterThan'
        threshold: 75
        contactEmails: !empty(budgetAlertEmail) ? [budgetAlertEmail] : []
        contactRoles: ['Owner', 'Contributor']
      }
      '90-percent': {
        enabled: contains(budgetAlertThresholds, 90)
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: !empty(budgetAlertEmail) ? [budgetAlertEmail] : []
        contactRoles: ['Owner', 'Contributor']
      }
      '100-percent': {
        enabled: contains(budgetAlertThresholds, 100)
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: !empty(budgetAlertEmail) ? [budgetAlertEmail] : []
        contactRoles: ['Owner', 'Contributor']
      }
    }
    filter: {
      and: [
        {
          dimensions: {
            name: 'ResourceGroupName'
            operator: 'In'
            values: [resourceGroup().name]
          }
        }
      ]
    }
  }
  tags: union(tags, costTrackingTags)
}

@description('Auto-shutdown schedule for non-production resources')
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (enableAutoShutdown && environmentType != 'Production') {
  name: autoShutdownName
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimezone
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
    targetResourceId: resourceGroup().id
  }
  tags: union(tags, costTrackingTags, {
    'Purpose': 'Cost optimization'
    'Component': 'Auto-shutdown'
  })
}

@description('Cost management export for detailed analysis')
resource costExport 'Microsoft.CostManagement/exports@2023-08-01' = {
  name: '${prefix}-cost-export'
  scope: resourceGroup()
  properties: {
    format: 'Csv'
    deliveryInfo: {
      destination: {
        resourceId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}'
        container: 'cost-reports'
        rootFolderPath: 'monthly'
      }
    }
    definition: {
      type: 'Usage'
      timeframe: 'MonthToDate'
      dataSet: {
        granularity: 'Daily'
        configuration: {
          columns: [
            'Date'
            'MeterName'
            'MeterCategory'
            'ResourceGroup'
            'ResourceName'
            'ResourceLocation'
            'ResourceType'
            'ServiceName'
            'ServiceTier'
            'Cost'
            'Currency'
            'ConsumedQuantity'
            'UnitOfMeasure'
          ]
        }
      }
    }
    schedule: {
      status: 'Active'
      recurrence: 'Monthly'
      recurrencePeriod: {
        from: dateTimeAdd(utcNow('yyyy-MM-dd'), 'P1D')
        to: dateTimeAdd(utcNow('yyyy-MM-dd'), 'P1Y')
      }
    }
  }
  tags: union(tags, costTrackingTags)
}

// == OUTPUTS ==
@description('The resource ID of the budget.')
output budgetId string = budget.id

@description('The name of the budget.')
output budgetName string = budget.name

@description('The resource ID of the auto-shutdown schedule.')
output autoShutdownId string = enableAutoShutdown && environmentType != 'Production' ? autoShutdown.id : ''

@description('The name of the auto-shutdown schedule.')
output autoShutdownName string = enableAutoShutdown && environmentType != 'Production' ? autoShutdown.name : ''

@description('Cost tracking tags to be applied to other resources.')
output costTrackingTags object = costTrackingTags