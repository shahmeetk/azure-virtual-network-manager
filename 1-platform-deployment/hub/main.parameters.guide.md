### Hub platform parameters guide (main.parameters.json)

This guide explains every parameter accepted by `1-platform-deployment/hub/main.bicep`, with usage examples, whether each parameter is mandatory or optional, and how to configure policy at Subscription or Management Group scope. Since JSON doesn’t allow comments, keep this guide next to your `main.parameters.json` and use it as the authoritative reference.

#### How to use
- Edit `main.parameters.json` and provide values under the `parameters` section as shown below.
- Run the hub deployment:
  ```bash
  az deployment group create \
    --resource-group <hub-rg> \
    --template-file azure-enterprise-bicep/1-platform-deployment/hub/main.bicep \
    --parameters @azure-enterprise-bicep/1-platform-deployment/hub/main.parameters.json
  ```
- Then run the policy deployment helper (optional):
  ```bash
  ./azure-enterprise-bicep/scripts/deploy-hub-and-sub-policy.sh \
    --subscription <subId> \
    --resource-group <hub-rg> \
    --location <location> \
    --params azure-enterprise-bicep/1-platform-deployment/hub/main.parameters.json \
    [--scope-type Subscription|ManagementGroup] \
    [--management-group-id <mgId>]
  ```

---

### Parameters

1) prefix
- Type: string
- Mandatory: Yes
- Purpose: Short unique prefix for naming AVNM resources.
- Example: `"test"` or `"corp"`

2) location
- Type: string
- Mandatory: Yes
- Purpose: Azure region for AVNM and hub resources.
- Example: `"eastus"`, `"westeurope"`

3) hubVnetId
- Type: string
- Mandatory: Yes
- Purpose: Resource ID of the existing Hub VNet to be used as the connectivity hub.
- Example: `/subscriptions/<subId>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<hub-vnet-name>`

4) subscriptionIds
- Type: array of strings
- Mandatory: Yes
- Purpose: Subscriptions that AVNM will manage. Accepts plain subscription GUIDs or full resource IDs.
- Example: `["<sub-guid-1>", "/subscriptions/<sub-guid-2>"]`

5) ipamPoolPrefix
- Type: string (CIDR)
- Mandatory: Yes (if you manage the IPAM pool here)
- Purpose: CIDR for the central IPAM pool used for spoke VNets.
- Example: `"10.0.0.0/17"`

6) deployConnectivity
- Type: bool
- Mandatory: Optional (default false in template)
- Purpose: Enables the AVNM connectivity configuration resource creation. Keep false until you’re ready to apply hub-and-spoke connectivity.
- Example: `true`

7) firewallPrivateIpAddress
- Type: string
- Mandatory: Optional
- Purpose: Private IP of the hub firewall. If set together with `internalSupernet`, routing is created to force Internet and internal traffic via the firewall.
- Example: `"10.0.255.4"` (leave empty to skip routing)

8) internalSupernet
- Type: string (CIDR)
- Mandatory: Optional
- Purpose: Internal supernet (e.g., your IPAM pool) for spoke-to-spoke traffic. Requires `firewallPrivateIpAddress` to enable routing.
- Example: `"10.0.0.0/17"`

9) enableSubscriptionPolicy
- Type: bool
- Mandatory: Optional (recommended true)
- Purpose: Signals your intent to deploy the unified AVNM onboarding policy that adds tagged VNets to the Spokes Network Group. Handled by the helper script/module.
- Example: `true`

10) includeTagName
- Type: string
- Mandatory: Optional (used when deploying policy)
- Purpose: The tag name that identifies VNets to auto-onboard to the Spokes Network Group.
- Default: `"avnm-group"`
- Example: `"avnm-group"`

11) includeTagValue
- Type: string
- Mandatory: Optional (used when deploying policy)
- Purpose: The tag value to include VNets.
- Default: `"spokes"`
- Example: `"spokes"`

12) policyScopeType
- Type: string (`"Subscription"` or `"ManagementGroup"`)
- Mandatory: Optional (used by scripts/modules during policy deployment)
- Purpose: Select where to deploy the AVNM policy. Subscription is default; MG is available when you need org-wide onboarding.
- Example: `"Subscription"` or `"ManagementGroup"`

13) policySubscriptionId
- Type: string
- Mandatory: Required when `policyScopeType = "Subscription"`
- Purpose: Subscription ID where the policy definition/assignment is created.
- Example: `"00000000-0000-0000-0000-000000000000"`

14) policyManagementGroupId
- Type: string
- Mandatory: Required when `policyScopeType = "ManagementGroup"`
- Purpose: Management Group ID (name) where the policy will be deployed.
- Example: `"contoso-platform"`

---

### Complete example (Subscription scope)
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "prefix": { "value": "corp" },
    "location": { "value": "eastus" },
    "hubVnetId": { "value": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub" },
    "subscriptionIds": { "value": ["00000000-0000-0000-0000-000000000000"] },
    "ipamPoolPrefix": { "value": "10.0.0.0/17" },
    "deployConnectivity": { "value": true },
    "firewallPrivateIpAddress": { "value": "10.0.255.4" },
    "internalSupernet": { "value": "10.0.0.0/17" },
    "enableSubscriptionPolicy": { "value": true },
    "includeTagName": { "value": "avnm-group" },
    "includeTagValue": { "value": "spokes" },
    "policyScopeType": { "value": "Subscription" },
    "policySubscriptionId": { "value": "00000000-0000-0000-0000-000000000000" },
    "policyManagementGroupId": { "value": "" }
  }
}
```

### Complete example (Management Group scope)
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "prefix": { "value": "corp" },
    "location": { "value": "eastus" },
    "hubVnetId": { "value": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub" },
    "subscriptionIds": { "value": ["00000000-0000-0000-0000-000000000000"] },
    "ipamPoolPrefix": { "value": "10.0.0.0/17" },
    "deployConnectivity": { "value": true },
    "firewallPrivateIpAddress": { "value": "10.0.255.4" },
    "internalSupernet": { "value": "10.0.0.0/17" },
    "enableSubscriptionPolicy": { "value": true },
    "includeTagName": { "value": "avnm-group" },
    "includeTagValue": { "value": "spokes" },
    "policyScopeType": { "value": "ManagementGroup" },
    "policySubscriptionId": { "value": "" },
    "policyManagementGroupId": { "value": "contoso-platform" }
  }
}
```

---

### Notes and best practices
- Start with `deployConnectivity=false` while you validate IPAM/groups and turn it on when ready.
- Provide both `firewallPrivateIpAddress` and `internalSupernet` to enforce all spoke traffic through the hub firewall.
- Use tags consistently on spoke VNets so the unified policy can auto-onboard them (`includeTagName`/`includeTagValue`).
- Choose `policyScopeType` based on your governance model; MG scope requires appropriate permissions and affects all subscriptions under that MG.
