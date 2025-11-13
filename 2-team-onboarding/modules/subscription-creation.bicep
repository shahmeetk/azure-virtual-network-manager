/*
  ====================================================================
  MODULE:   subscription-creation.bicep
  SCOPE:    Tenant
  DESC:     Creates a new Azure subscription under a specified
            billing account and places it in the target management group.
  ====================================================================
*/

targetScope = 'tenant'

// === PARAMETERS ===
@description('The alias for the new subscription. This must be unique.')
@minLength(1)
param subscriptionAliasName string

@description('The display name for the new subscription.')
@minLength(1)
param subscriptionDisplayName string

@description('The full resource ID of the billing account scope (e.g., /providers/Microsoft.Billing/billingAccounts/{billingAccountName}/enrollmentAccounts/{enrollmentAccountName}).')
param billingAccountScope string

@description('The target management group ID for the new subscription.')
param targetManagementGroupId string

// === RESOURCES ===
@description('Creates the subscription alias. This is an asynchronous operation; the subscription itself will be created in the background.')
resource subscriptionAlias 'Microsoft.Subscription/aliases@2021-10-01' = {
  name: subscriptionAliasName
  properties: {
    displayName: subscriptionDisplayName
    workload: 'Production' // Or 'DevTest'
    billingScope: billingAccountScope
    managementGroupId: targetManagementGroupId
  }
}

// === OUTPUTS ===
@description('The name of the subscription alias created.')
output subscriptionAliasName string = subscriptionAlias.name

@description('The full resource ID of the subscription alias.')
output subscriptionAliasId string = subscriptionAlias.id
