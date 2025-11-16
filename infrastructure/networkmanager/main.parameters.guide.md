### Hub platform parameters guide (main.parameters.json)

This guide explains parameters for `infrastructure/networkmanager/main.bicep`. Keep this next to `main.parameters.json`.

#### How to use
- Edit `main.parameters.json` and provide values under the `parameters` section as shown below.
- Run the hub deployment:
  ```bash
  az deployment group create \
    --resource-group <hub-rg> \
    --template-file infrastructure/networkmanager/main.bicep \
    --parameters @infrastructure/networkmanager/main.parameters.json
  ```
- Then run the policy deployment helper (optional):
  ```bash
  ./scripts/deploy-hub-and-sub-policy.sh \
    --subscription <subId> \
    --resource-group <hub-rg> \
    --location <location> \
    --params infrastructure/networkmanager/main.parameters.json \
    [--scope-type Subscription|ManagementGroup] \
    [--management-group-id <mgId>]
  ```

---

### Parameters
- `prefix` (required): Naming prefix for resources
- `location` (required): Azure region
- `hubResourceGroupName` (required): Resource Group containing the hub VNet
- `hubVnetName` (required): Hub VNet name
- `hubVnetSizeInBits` (optional): CIDR size bits for hub VNet (default 20)
- `hubSubscriptionId` (required): Subscription ID used for AVNM
- `managedScopeType` (required): `Subscription` or `ManagementGroup`
- `managedScopeId` (required): Subscription GUID or MG ID
- `ipamPoolPrefix` (required): CIDR for IPAM pool
- `deployConnectivity` (optional): Whether to deploy connectivity config
- `useHubGateway` (optional): Use hub gateway transit
- `isGlobalConnectivity` (optional): Global across regions
- `deleteExistingPeering` (optional): Remove manual peerings
- `firewallPrivateIpAddress` (optional): Hub Firewall private IP
- `internalSupernet` (optional): Supernet CIDR to route via firewall
- `includeTagName` (optional): Tag key for auto-onboarding
- `includeTagValue` (optional): Tag value for auto-onboarding
- `environment` (required): `Development|Test|Production`
- `resourceTags` (optional): Additional tags object
- `createHubVnetIfMissing` (optional): Create hub VNet from IPAM when true

### Change Log
- 1.1.2: Removed obsolete `hubVnetId`; added `hubResourceGroupName` + `hubVnetName`; clarified AVNM configs defaults and managed routing.