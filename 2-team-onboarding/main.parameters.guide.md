### Team Onboarding parameters guide (2-team-onboarding/main.parameters.json)

This guide documents every parameter used by `2-team-onboarding/main.bicep` and the subscription-scope variant `subscription-main.bicep`. Since JSON doesn’t allow comments, keep this guide next to your parameters file.

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
0) onboardingMode
- Type: string
- Mandatory: No (defaults to `managementGroup` in `main.bicep`; script defaults to `subscription` if not set)
- Purpose: Controls whether onboarding is done at tenant scope (creating MG + subscriptions) or within the current subscription (creating RGs + VNets).
- Allowed: "managementGroup", "subscription"
- Example: "subscription"

1) teamName
- Type: string
- Mandatory: Yes
- Purpose: Short unique team name used in resource naming (e.g., MG, subscriptions, VNets).
- Example: "teamc"

2) parentManagementGroupId
- Type: string
- Mandatory: Yes (managementGroup mode only)
- Purpose: Management Group under which the team MG will be created.
- Example: "contoso-platform" (not display name; use MG ID)

3) billingScope
- Type: string
- Mandatory: Yes (managementGroup mode only)
- Purpose: Full billing scope resource ID used for subscription creation.
- Example: "/providers/Microsoft.Billing/billingAccounts/0000:1111-22@33333333-4444-5555-6666-777777777777:8888_2025-01-01/providers/Microsoft.Billing/billingProfiles/ABCDEF/providers/Microsoft.Billing/invoiceSections/XYZ"

4) location
- Type: string
- Mandatory: Yes
- Purpose: Azure region for deployment records and spoke resources.
- Example: "eastus"

5) environments
- Type: array(string)
- Mandatory: Optional (default ["dev","uat","prod"]) 
- Purpose: Environments to create. In managementGroup mode: one subscription + VNet per entry. In subscription mode: one Resource Group + VNet per entry in the current subscription.
- Allowed values (template enforced individually): dev, uat, prod, test, staging
- Example: ["dev","uat","prod"]

6) ipamPoolId
- Type: string
- Mandatory: Yes
- Purpose: Resource ID of the AVNM IPAM pool from hub deployment outputs.
- Example: "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/networkManagers/<avnm>/ipamPools/<poolName>"

7) vnetSizeInBits
- Type: int
- Mandatory: Optional (default 24)
- Purpose: Size of each spoke VNet (e.g., 24 for /24).
- Allowed: 16–28
- Example: 24

8) maxRetries
- Type: int
- Mandatory: Optional (default 3)
- Purpose: Retry attempts for subscription creation.
- Allowed: 1–10

9) retryDelaySeconds
- Type: int
- Mandatory: Optional (default 60)
- Purpose: Delay between retries for subscription creation.
- Allowed: 30–300

10) enableLogging
- Type: bool
- Mandatory: Optional (default true)
- Purpose: Enables verbose logging in subscription creation module.

11) includeTagName
- Type: string
- Mandatory: Optional (default "avnm-group")
- Purpose: Tag name that AVNM policy uses to auto-onboard VNets to the Spokes Network Group.

12) includeTagValue
- Type: string
- Mandatory: Optional (default "spokes")
- Purpose: Tag value that AVNM policy uses to auto-onboard VNets to the Spokes Network Group.

Complete example
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "teamName": { "value": "teamc" },
    "parentManagementGroupId": { "value": "contoso-platform" },
    "billingScope": { "value": "/providers/Microsoft.Billing/billingAccounts/.../invoiceSections/..." },
    "location": { "value": "eastus" },
    "environments": { "value": ["dev","uat","prod"] },
    "ipamPoolId": { "value": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/networkManagers/<avnm>/ipamPools/<pool>" },
    "vnetSizeInBits": { "value": 24 },
    "maxRetries": { "value": 3 },
    "retryDelaySeconds": { "value": 60 },
    "enableLogging": { "value": true },
    "includeTagName": { "value": "avnm-group" },
    "includeTagValue": { "value": "spokes" }
  }
}
```

Notes
- Ensure the hub has been deployed and you have the `ipamPoolId` output available.
- The VNets created will be auto-onboarded by the AVNM policy when you’ve deployed it at Subscription or MG scope with matching tag name/value.
- Use `--what-if` for a safe preview before applying.

Subscription-mode minimal parameters
```json
{
  "parameters": {
    "onboardingMode": { "value": "subscription" },
    "teamName": { "value": "TeamX" },
    "location": { "value": "eastus" },
    "environments": { "value": ["dev", "uat", "prod"] },
    "ipamPoolId": { "value": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/networkManagers/<avnm>/ipamPools/<pool>" },
    "vnetSizeInBits": { "value": 24 },
    "includeTagName": { "value": "avnm-group" },
    "includeTagValue": { "value": "spokes" }
  }
}
```
