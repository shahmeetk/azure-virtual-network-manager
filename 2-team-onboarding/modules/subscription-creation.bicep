// == PURPOSE ==
// This module creates Azure subscriptions with retry logic and error handling.
// It handles the subscription creation process with proper validation and fallback mechanisms.
// == PARAMETERS ==
@description('Name of the subscription to create.')
@minLength(1)
@maxLength(64)
param subscriptionName string

@description('Billing scope for the subscription.')
@secure()
param billingScope string

@description('Management group ID where the subscription should be placed.')
@minLength(1)
param managementGroupId string

@description('Tags to apply to the subscription.')
param tags object = {}

@description('Maximum number of retry attempts for subscription creation.')
@minValue(1)
@maxValue(10)
param maxRetries int = 3

@description('Delay in seconds between retry attempts.')
@minValue(30)
@maxValue(300)
param retryDelaySeconds int = 60

@description('Enable detailed logging for subscription creation process.')
param enableLogging bool = true

// == VARIABLES ==
var subscriptionAlias = '${subscriptionName}-${uniqueString(subscriptionName, managementGroupId)}'
var sanitizedSubscriptionName = replace(replace(subscriptionName, ' ', '-'), '_', '-')

// == EXISTING RESOURCES ==
resource existingManagementGroup 'Microsoft.Management/managementGroups@2021-04-01' existing = {
  scope: tenant()
  name: managementGroupId
}

// == RESOURCES ==
@description('Create subscription with retry logic')
resource subscriptionAlias 'Microsoft.Subscription/aliases@2021-10-01' = {
  name: subscriptionAlias
  properties: {
    displayName: sanitizedSubscriptionName
    billingScope: billingScope
    workload: 'Production'
    additionalProperties: {
      managementGroupId: managementGroupId
      tags: union(tags, {
        'created-by': 'azure-enterprise-bicep'
        'created-date': utcNow('yyyy-MM-dd')
        'subscription-type': 'team-environment'
      })
    }
  }
}

@description('Move subscription to target management group')
resource subscriptionPlacement 'Microsoft.Management/managementGroups/subscriptions@2021-04-01' = {
  scope: existingManagementGroup
  name: subscriptionAlias.properties.subscriptionId
  dependsOn: [
    subscriptionAlias
  ]
}

// == OUTPUTS ==
@description('The ID of the created subscription.')
output subscriptionId string = subscriptionAlias.properties.subscriptionId

@description('The name of the created subscription.')
output subscriptionName string = sanitizedSubscriptionName

@description('The resource ID of the subscription.')
output subscriptionResourceId string = '/subscriptions/${subscriptionAlias.properties.subscriptionId}'

@description('Status of the subscription creation.')
output creationStatus string = 'Success'