### Hub platform parameters guide (main.parameters.json)

This guide explains every parameter accepted by `infrastructure/networkmanager/main.bicep`, with usage examples, whether each parameter is mandatory or optional, and how to configure policy at Subscription or Management Group scope. Since JSON doesn’t allow comments, keep this guide next to your `main.parameters.json` and use it as the authoritative reference.

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
- Same as previously documented for hub platform deployment.

### Change Log
- 1.1.1: Updated paths to `infrastructure/networkmanager`.