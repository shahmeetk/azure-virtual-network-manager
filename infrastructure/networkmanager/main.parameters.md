# Hub Deployment Parameters (main.parameters.json)

Version: 1.1.1

## Required Parameters
- `prefix`: Short identifier for naming resources (e.g., `test`).
- `location`: Azure region for hub resources (e.g., `eastus`).
- `hubVnetId`: Full resource ID of the existing hub VNet.
- `subscriptionIds`: Array of subscription IDs (or resource IDs) AVNM will manage.
- `ipamPoolPrefix`: CIDR block for IPAM pool (e.g., `172.16.128.0/17`).

## Optional Parameters
- `deployConnectivity`: `true|false`. When true, deploy connectivity config.
- `firewallPrivateIpAddress`: Hub firewall private IP for routing rules.
- `internalSupernet`: Supernet CIDR to route via firewall (e.g., IPAM supernet).
- `includeTagName`: Tag key used by policy to auto-onboard VNets (default `avnm-group`).
- `includeTagValue`: Tag value used by policy (default `spokes`).

## Notes
- Connectivity and routing are applied only when required inputs are provided.
- Policy deploy script reads `includeTagName` and `includeTagValue` from this file.

## Change Log
- 1.1.1: Updated paths to `infrastructure/networkmanager`.