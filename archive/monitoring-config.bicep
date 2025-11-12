// == PURPOSE ==
// This module configures comprehensive monitoring and logging for the enterprise infrastructure.
// It includes Log Analytics workspace, diagnostic settings, alerts, and monitoring dashboards.
// == PARAMETERS ==
@description('The Azure region where monitoring resources will be deployed.')
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

@description('Prefix for naming monitoring resources.')
@minLength(3)
@maxLength(10)
@pattern('^[a-z][a-z0-9-]*[a-z0-9]$')
param prefix string

@description('Log Analytics workspace name. If empty, will be auto-generated.')
param logAnalyticsWorkspaceName string = ''

@description('Application Insights name. If empty, will be auto-generated.')
param applicationInsightsName string = ''

@description('Alert action group name. If empty, will be auto-generated.')
param alertActionGroupName string = ''

@description('Email address for alert notifications.')
param alertEmail string = ''

@description('Enable Application Insights for monitoring.')
param enableApplicationInsights bool = true

@description('Retention days for logs in Log Analytics workspace.')
@allowed([30, 60, 90, 120, 180, 270, 365, 550, 730])
param logRetentionDays int = 90

@description('Tags to apply to monitoring resources.')
param tags object = {}

// == VARIABLES ==
var workspaceName = !empty(logAnalyticsWorkspaceName) ? logAnalyticsWorkspaceName : '${prefix}-workspace-${uniqueString(resourceGroup().id)}'
var insightsName = !empty(applicationInsightsName) ? applicationInsightsName : '${prefix}-insights-${uniqueString(resourceGroup().id)}'
var actionGroupName = !empty(alertActionGroupName) ? alertActionGroupName : '${prefix}-alerts-${uniqueString(resourceGroup().id)}'

// == RESOURCES ==
@description('Log Analytics workspace for centralized logging')
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: union(tags, {
    'Purpose': 'Centralized logging'
    'Component': 'Log Analytics'
  })
}

@description('Application Insights for application monitoring')
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: union(tags, {
    'Purpose': 'Application monitoring'
    'Component': 'Application Insights'
  })
}

@description('Action group for alert notifications')
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  properties: {
    groupShortName: '${prefix}-alerts'
    enabled: true
    emailReceivers: !empty(alertEmail) ? [
      {
        name: 'PrimaryEmail'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ] : []
    smsReceivers: []
    webhookReceivers: []
  }
  tags: tags
}

@description('Network connectivity monitoring alert')
resource networkAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${prefix}-network-connectivity-alert'
  location: 'Global'
  properties: {
    description: 'Alert when network connectivity drops below threshold'
    severity: 2
    enabled: true
    scopes: [resourceGroup().id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          name: 'NetworkDroppedPackets'
          metricName: 'DroppedPackets'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
  tags: tags
}

@description('Resource health monitoring alert')
resource resourceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: '${prefix}-resource-health-alert'
  location: 'Global'
  properties: {
    description: 'Alert on resource health events'
    enabled: true
    scopes: [resourceGroup().id]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'status'
          equals: 'Active'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
  tags: tags
}

@description('Diagnostic setting for resource group')
resource rgDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}-rg-diagnostics'
  scope: resourceGroup()
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'Administrative'
        enabled: true
      }
      {
        category: 'Security'
        enabled: true
      }
      {
        category: 'ServiceHealth'
        enabled: true
      }
      {
        category: 'Alert'
        enabled: true
      }
      {
        category: 'Recommendation'
        enabled: true
      }
      {
        category: 'Policy'
        enabled: true
      }
      {
        category: 'Autoscale'
        enabled: true
      }
      {
        category: 'ResourceHealth'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// == OUTPUTS ==
@description('The resource ID of the Log Analytics workspace.')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('The name of the Log Analytics workspace.')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('The resource ID of the Application Insights component.')
output applicationInsightsId string = enableApplicationInsights ? appInsights.id : ''

@description('The instrumentation key of the Application Insights component.')
output applicationInsightsKey string = enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''

@description('The resource ID of the alert action group.')
output alertActionGroupId string = actionGroup.id

@description('The name of the alert action group.')
output alertActionGroupName string = actionGroup.name
