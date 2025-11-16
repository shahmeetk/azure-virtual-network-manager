### Team Onboarding parameters guide (infrastructure/spoke-team-onboarding/main.parameters.json)

This guide documents every parameter used by `infrastructure/spoke-team-onboarding/subscription-main.bicep`. Since JSON doesn’t allow comments, keep this guide next to your parameters file.

How to deploy
- What-if (safe preview):
  ```bash
  ./scripts/onboard-team.sh \
    --subscription <context-sub-id> \
    --location eastus \
    --params infrastructure/spoke-team-onboarding/main.parameters.json \
    --what-if
  ```
- Actual deployment:
  ```bash
  ./scripts/onboard-team.sh \
    --subscription <context-sub-id> \
    --location eastus \
    --params infrastructure/spoke-team-onboarding/main.parameters.json
  ```

Parameters
- `subscriptionId` (optional): Azure subscription ID used by scripts when not passed via CLI
- `location` (required): Azure region for deployment record
- `environment` (required): `Development | Test | Production`
- `ipamPoolId` (required): Resource ID of IPAM pool from hub outputs
- `vnetSizeInBits` (optional): VNet CIDR size bits; defaults to 24
- `spokeResourceGroupName` (required): Name of the RG to create/use for the spoke VNet
- `resourceTags` (optional): Additional tags merged onto resources (include `avnm-group: spokes` for dynamic onboarding)
- `vnetName` (optional): Explicit VNet name to create or update; default is `vnet-<spokeResourceGroupName>-<environment>`

Change Log
- 1.1.2: Added `vnetName` and removed unused `virtualNetworkAddressPrefixes` in subscription flow.