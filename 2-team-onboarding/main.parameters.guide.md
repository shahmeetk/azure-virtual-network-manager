### Team Onboarding parameters guide (2-team-onboarding/main.parameters.json)

This guide documents every parameter used by `2-team-onboarding/subscription-main.bicep`. Since JSON doesn’t allow comments, keep this guide next to your parameters file.

How to deploy
- What-if (safe preview):
  ```bash
  ./azure-enterprise-bicep/scripts/onboard-team.sh \
    --subscription <context-sub-id> \
    --location eastus \
    --params azure-enterprise-bicep/2-team-onboarding/main.parameters.json \
    --what-if
  ```
- Actual deployment:
  ```bash
  ./azure-enterprise-bicep/scripts/onboard-team.sh \
    --subscription <context-sub-id> \
    --location eastus \
    --params azure-enterprise-bicep/2-team-onboarding/main.parameters.json
  ```

Parameters
0) teamName
- Type: string
- Mandatory: Yes
- Purpose: Short unique team name used in resource naming (e.g., VNet).
- Example: "teamc"

1) location
- Type: string
- Mandatory: Yes
- Purpose: Azure region for RG and VNet deployment.
- Example: "eastus"

2) environment
- Type: string
- Mandatory: Yes
- Purpose: Environment name (e.g., dev, uat, prod).
- Allowed: dev, uat, prod, test, staging

3) ipamPoolId
- Type: string (secure)
- Mandatory: Yes
- Purpose: Resource ID of the AVNM IPAM Pool from hub deployment output.

4) vnetSizeInBits
- Type: int
- Mandatory: Yes
- Purpose: VNet CIDR size (e.g., 24 for /24). Supported: 16–28.

5) includeTagName
- Type: string
- Mandatory: No
- Purpose: Tag key for AVNM policy auto-onboarding. Default: `avnm-group`.

6) includeTagValue
- Type: string
- Mandatory: No
- Purpose: Tag value for AVNM policy auto-onboarding. Default: `spokes`.

7) spokeResourceGroupName
- Type: string
- Mandatory: Yes
- Purpose: Name of the spoke RG to create or reuse.


Complete example (subscription mode)
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "teamName": { "value": "teamc" },
    "location": { "value": "eastus" },
    "environment": { "value": "dev" },
    "spokeResourceGroupName": { "value": "rg-teamc-dev-net" },
    "ipamPoolId": { "value": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/networkManagers/<avnm>/ipamPools/<pool>" },
    "vnetSizeInBits": { "value": 24 },
    "includeTagName": { "value": "avnm-group" },
    "includeTagValue": { "value": "spokes" }
  }
}
```

Notes
- Ensure the hub has been deployed and you have the `ipamPoolId` output available.
- Use `--what-if` for a safe preview before applying.

Change Log
- 1.1.0: Updated for subscription-only mode; removed MG parameters; added `environment`, `spokeResourceGroupName`, `includeTagName`.
