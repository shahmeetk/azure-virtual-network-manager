/*
  ====================================================================
  FILE:     subscription-main.bicep (Team Onboarding - Subscription Mode)
  SCOPE:    Subscription
  DESC:     Onboards a team within the current subscription by creating
            a Resource Group and a VNet per the provided environment,
            using AVNM IPAM to allocate address space.
  ====================================================================
*/

targetScope = 'subscription'

// === PARAMETERS ===
@description('Short, unique name for the new team (e.g., "TeamA"). Used for naming.')
@minLength(2)
@maxLength(24)
param teamName string

@description('The Azure region to deploy the spoke VNet resources into.')
param location string

@description('Environment name (e.g., dev, uat, prod).')
param environment string

@description('The Resource ID of the AVNM IPAM Pool (from hub deployment output).')
@secure()
@minLength(10)
param ipamPoolId string

@description('The size of the VNet as a CIDR bit (e.g., 24 for a /24).')
@allowed([ 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28 ])
param vnetSizeInBits int = 24

@description('Tag name used by policy to auto-onboard VNets to the Spokes Network Group (optional).')
param includeTagName string = 'avnm-group'

@description('Tag value used by policy to auto-onboard VNets to the Spokes Network Group (optional).')
param includeTagValue string = 'spokes'

// === MODULES ===
module spokeInfra 'modules/spoke-infra-deploy.bicep' = {
  name: 'deploy-spoke-${teamName}-${environment}'
  params: {
    location: location
    teamName: teamName
    environment: environment
    ipamPoolId: ipamPoolId
    vnetSizeInBits: vnetSizeInBits
    includeTagName: includeTagName
    includeTagValue: includeTagValue
  }
}

// === OUTPUTS ===
@description('Echo the deployment mode used.')
output onboardingMode string = 'subscription'