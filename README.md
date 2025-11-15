# Azure Enterprise Bicep Infrastructure

A modular, production‑ready Azure landing zone built with Bicep. It implements enterprise networking, security, and governance using Azure Virtual Network Manager (AVNM) with a hub‑and‑spoke topology, plus automation scripts for validation, testing, CI/CD, and backup/restore.


## Overview

This repository provides two main deployment flows:
- Platform hub provisioning at Resource Group scope (AVNM + IPAM + configs + policy).
- Team onboarding at Subscription scope (create or reuse a spoke Resource Group and deploy a spoke VNet allocated from IPAM).

You can use the provided scripts to validate, test (what‑if or real), and automate deployments across environments.


## Stack and Tooling

- Language/IaC: Bicep (ARM)
- Cloud: Microsoft Azure
- CLIs: Azure CLI (+ Bicep CLI)
- Shell scripts: Bash (macOS/Linux; Windows via WSL/Git Bash)
- Package manager: None (CLI tools only)

Entry points:
- Platform hub: `infrastructure/networkmanager/main.bicep` (targetScope: `resourceGroup`)
- Team onboarding: `infrastructure/spoke-team-onboarding/subscription-main.bicep` (targetScope: `subscription`)

Automation scripts (under `azure-enterprise-bicep/scripts/`):
- `validate-bicep.sh` — compile/validate and basic static checks
- `test-deployment.sh` — parameter validation, what‑if, optional test deploy and cleanup
- `ci-cd-pipeline.sh` — validate → test → deploy pipeline stages
- `backup-restore.sh` — backup/restore utilities for critical components


## Project Structure

```
azure-virtual-network-manager/
├── infrastructure/
│   ├── networkmanager/
│   │   ├── main.bicep
│   │   ├── main.parameters.json
│   │   └── modules/
│   │       ├── avnm-core.bicep
│   │       ├── avnm-policy.bicep
│   │       ├── mg-avnm-policy.bicep
│   │       ├── avnm-configs.bicep
│   │       └── vnet-from-ipam.bicep
│   └── spoke-team-onboarding/
│       ├── subscription-main.bicep
│       ├── main.parameters.json
│       └── modules/
│           ├── spoke-infra-deploy.bicep
│           └── vnet-from-ipam.bicep
└── scripts/
    ├── validate-bicep.sh
    ├── test-deployment.sh
    ├── ci-cd-pipeline.sh
    └── deploy-hub-and-sub-policy.sh
```

Note: The project has been streamlined. Legacy management‑group onboarding and deprecated modules/scripts have been removed.


## Requirements

Software (local machine or CI runner):
- Azure CLI 2.50.0+ (`az --version`)
- Bicep CLI 0.20.0+ (`az bicep install` will install/manage it)
- Bash (5.x recommended)

Azure prerequisites:
- Existing Hub VNet
- Azure Firewall (optional in minimal deployment). Routing to a firewall is disabled by default and can be enabled later.
- Management Group hierarchy in place
- Permissions:
  - Management Group: Resource Policy Contributor (to deploy policy) — optional in minimal deployment
  - Hub Resource Group: Owner or Contributor (platform hub)
- Billing scope with rights to create subscriptions (for team onboarding)


## Setup

1) Login and set subscription/context
```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
```

2) (Optional) Install/update Bicep
```bash
az bicep install
```

3) Clone this repository and change directory
```bash
cd azure-enterprise-bicep
```


## Deploy: Platform Hub (resourceGroup scope)

Template: `infrastructure/networkmanager/main.bicep`

What this deploys (minimal, subscription-scope AVNM):
- Azure Virtual Network Manager (AVNM) scoped to your subscription
- IPAM Pool with a static CIDR (addressPrefixes)
- Network Groups: hub (static; adds your hub VNet as static member) and spokes (dynamic)
- Security Admin baseline (rule collection + deny-RDP rule)
- Connectivity configuration is disabled by default due to a service-side issue in your tenant; use the auto-probe script to test variants safely.

Key parameters (minimal):
- `prefix` (string): naming prefix
- `location` (string): region (defaults to `resourceGroup().location`)
- `hubVnetId` (secure string): resource ID of existing hub VNet
- `subscriptionIds` (array): subscription IDs to scope AVNM (e.g., `["<subId>"]`)
- `ipamPoolPrefix` (string): CIDR for IPAM pool (e.g., `10.0.0.0/10`)
- `deployConnectivity` (bool): default false; enable later after a successful auto‑probe

Notes:
- Optional modules (security, monitoring, cost, backup, DR) are disabled by default in this minimal deployment.
- Azure Firewall is optional. Routing to a firewall is disabled by default and can be enabled later by providing firewall details.

Example deployment:
```bash
# Create or select a resource group for the platform hub
az group create -n platform-hub-rg -l eastus

# Create parameters file
cat > hub.parameters.json <<'JSON'
{
  "prefix": { "value": "ent" },
  "location": { "value": "eastus" },
  "hubVnetId": { "value": "/subscriptions/<sub-id>/resourceGroups/hub-network-rg/providers/Microsoft.Network/virtualNetworks/hub-vnet" },
  "parentManagementGroupId": { "value": "platform-mg" },
  "ipamPoolPrefix": { "value": "10.0.0.0/10" }
}
JSON

# Deploy
az deployment group create \
  --name platform-hub-deployment \
  --resource-group platform-hub-rg \
  --template-file infrastructure/networkmanager/main.bicep \
  --parameters @infrastructure/networkmanager/main.parameters.json
```

### Alternative: Deploy via Azure Portal (Custom template)
1) Build Bicep to ARM JSON:
```bash
cd azure-enterprise-bicep/1-platform-deployment/hub
az bicep build --file main.bicep --outdir ./dist
```
2) In Portal, open "Deploy a custom template" → "Build your own template in the editor" → Load `./dist/main.json`.
3) Select your subscription and Resource Group, enter parameters (`prefix`, `location`, `hubVnetId`, `parentManagementGroupId`, `ipamPoolPrefix`), then Review + Create.

### Post‑deployment: Publish AVNM configurations (commit/apply)
Creating AVNM objects does not automatically apply them to VNets. Commit the configs per region.

Portal method:
1) Azure Virtual Network Manager → `${prefix}-avnm` → Network Manager deployments → Create
2) Select Connectivity and Security Admin configs (Routing is off by default unless firewall is provided)
3) Scope: choose your MG/subscriptions, Regions: choose hub/spoke regions → Deploy

CLI method (example):
```bash
RG=platform-hub-rg
AVNM_NAME=ent-avnm
REGION=eastus

# Connectivity commit
az network manager deployment create \
  --resource-group $RG \
  --network-manager-name $AVNM_NAME \
  --location $REGION \
  --commit-type Connectivity \
  --configuration-ids $(az network manager connectivity-configuration list -g $RG --network-manager-name $AVNM_NAME --query "[].id" -o tsv)

# Security admin commit
az network manager deployment create \
  --resource-group $RG \
  --network-manager-name $AVNM_NAME \
  --location $REGION \
  --commit-type SecurityAdmin \
  --configuration-ids $(az network manager security-admin-configuration list -g $RG --network-manager-name $AVNM_NAME --query "[].id" -o tsv)
```

### Validate in Portal
- AVNM exists: Virtual Network Manager → `${prefix}-avnm` → Overview
- Network groups: `ng-hub-static` contains your hub VNet; `ng-spokes-dynamic` initially empty
- Optional: Tag a spoke VNet `avnm-group=spokes` (requires policy; see next section)

### Optional: Deploy AVNM Spokes Tagging Policy (Management Group scope)
The minimal deployment comments out policy. To enable dynamic membership, deploy `1-platform-deployment/hub/modules/avnm-policy.bicep` at MG scope:
```bash
MG_ID=platform-mg
SPOKES_NG_ID=<copy from hub deployment output or AVNM → Network groups>
az deployment mg create \
  --name avnm-policy \
  --management-group-id $MG_ID \
  --template-file azure-enterprise-bicep/1-platform-deployment/hub/modules/avnm-policy.bicep \
  --parameters spokesNetworkGroupId=$SPOKES_NG_ID
```

### Re‑enable optional modules and routing
- Monitoring/Cost/Backup/DR: Uncomment the respective module blocks in `1-platform-deployment/hub/main.bicep`.
- Routing via Firewall: Provide `firewallPrivateIpAddress` and `internalSupernet` to `avnm-configs.bicep` (add these params under the `avnmConfigs` module block in `main.bicep`). When both are non‑empty, routing resources are created and can be committed.


## Deploy: Team Onboarding (tenant scope)

Template: `infrastructure/spoke-team-onboarding/subscription-main.bicep`

Key parameters:
- `teamName` (string)
- `parentManagementGroupId` (string)
- `billingScope` (secure string): full resource ID of billing scope
- `location` (string)
- `ipamPoolId` (secure string): Resource ID of IPAM pool from hub deployment outputs
- `vnetSizeInBits` (int, default 24)
- `environments` (array, default `["dev","uat","prod"]`)

Example deployment:
```bash
cat > team.parameters.json <<'JSON'
{
  "teamName": { "value": "TeamA" },
  "parentManagementGroupId": { "value": "platform-mg" },
  "billingScope": { "value": "/providers/Microsoft.Billing/billingAccounts/<...>/enrollmentAccounts/<...>" },
  "location": { "value": "eastus" },
  "ipamPoolId": { "value": "<IPAM_POOL_RESOURCE_ID>" },
  "vnetSizeInBits": { "value": 24 },
  "environments": { "value": ["dev","uat","prod"] }
}
JSON

# Team Onboarding (dual mode)
# Subscription-scope example (no MG permissions required)
./scripts/onboard-team.sh \
  --subscription <context-sub-id> \
  --location eastus \
  --params 2-team-onboarding/team-b.subscription.parameters.json

# Tenant-scope example (creates MG + subscriptions)
./scripts/onboard-team.sh \
  --subscription <context-sub-id> \
  --location eastus \
  --params 2-team-onboarding/team-b.parameters.json \
  --mode managementGroup
```

TODO: Document how to retrieve `ipamPoolId` from hub deployment outputs once final outputs are confirmed in `1-platform-deployment/hub/modules/avnm-core.bicep`.


## Scripts

All scripts live in `azure-enterprise-bicep/scripts/`. See `scripts/README.md` for detailed help. Common usage:

Validation:
```bash
./scripts/validate-bicep.sh
```

Test deployment (what‑if by default):
```bash
# Validation only
./scripts/test-deployment.sh --validation-only

# Full test with params
./scripts/test-deployment.sh --location eastus --prefix test --environment dev --dry-run false
```

CI/CD pipeline (stages: validate → test → deploy):
```bash
# Run a single stage
./scripts/ci-cd-pipeline.sh validate
./scripts/ci-cd-pipeline.sh test
./scripts/ci-cd-pipeline.sh deploy-dev

# With options
./scripts/ci-cd-pipeline.sh -e prod -l eastus -p ent --dry-run deploy-prod
```

Backup/Restore utilities:
```bash
./scripts/backup-restore.sh backup
./scripts/backup-restore.sh restore
```


## Environment Variables and Script Flags

`ci-cd-pipeline.sh` reads environment variables (with defaults):
- `ENVIRONMENT` (default: `dev`)
- `LOCATION` (default: `eastus`)
- `PREFIX` (default: `cdm`)
- `SUBSCRIPTION_ID` (no default)

All scripts also accept flags; see `--help` in each script. Examples:
- `test-deployment.sh`: `--location`, `--prefix`, `--environment`, `--dry-run`, `--validation-only`
- `ci-cd-pipeline.sh`: `--environment`, `--location`, `--prefix`, `--subscription`, `--dry-run`, `--skip-validation`, `--skip-tests`
- `backup-restore.sh`: `--location`, `--prefix`, `--environment`, `--operation`


## Testing

This repo uses scripts to validate and test deployments:
- Static validation: `./scripts/validate-bicep.sh` (compilation + basic security/convention checks)
- Safe testing: `./scripts/test-deployment.sh --validation-only` (no changes) or with `--dry-run false` to actually deploy to a test environment

TODO: Add automated unit/lint tests and a `tests/` folder if deeper testing is required.


## Notes on AVNM Configurations

- Connectivity: Hub‑and‑Spoke via `modules/avnm-configs.bicep` (enabled by default)
- Routing: Optional and disabled by default in minimal deployment; when you supply `firewallPrivateIpAddress` and `internalSupernet`, routing rules will be created to send 0.0.0.0/0 and internal supernet traffic to the hub firewall
- Security Admin Config: Baseline Security Admin configuration is created; commit/apply it after deployment via AVNM Deployments


## Troubleshooting

- Ensure you’re logged in (`az login`) and targeting the correct subscription (`az account show`).
- Team onboarding requires tenant‑level permissions and a valid `billingScope` with rights to create subscriptions.
- If AVNM policy assignment errors occur, verify `parentManagementGroupId` and assignment scope.


## License

MIT intended. TODO: Add a `LICENSE` file to the repo or update this section with the actual license used by your organization.


## Changelog
- 2025‑11‑07: README rewritten to reflect actual files, entry points, scripts, and accurate commands; removed references to non‑existent folders; added TODOs where outputs/licensing info are unknown.

## 📁 Repository Structure

```
azure-enterprise-bicep/
├── 1-platform-deployment/          # Central platform infrastructure
│   └── hub/
│       ├── main.bicep              # Main platform hub deployment
│       ├── main.parameters.json    # Parameter template
│       └── modules/                # Platform-specific modules
│           ├── avnm-core.bicep     # AVNM and IPAM deployment
│           ├── avnm-policy.bicep   # Azure Policy for AVNM
│           ├── avnm-configs.bicep  # AVNM configurations
│           ├── security-config.bicep # Security and RBAC
│           ├── monitoring-config.bicep # Monitoring and logging
│           └── cost-optimization.bicep # Cost management
├── 2-team-onboarding/            # Team onboarding automation
│   ├── main.bicep                # Main team onboarding
│   └── modules/                  # Team-specific modules
│       ├── management-group.bicep  # Management group creation
│       ├── subscription-creation.bicep # Subscription with retry logic
│       ├── spoke-infra-deploy.bicep # Spoke infrastructure
│       └── vnet-from-ipam.bicep    # VNet from IPAM pool
├── scripts/                      # Deployment and validation scripts
├── tests/                        # Test frameworks and validations
└── docs/                         # Additional documentation
```

## 🔧 Configuration

### Platform Hub Configuration

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `prefix` | Resource naming prefix | - | Yes |
| `location` | Azure region | resourceGroup().location | Yes |
| `hubVnetId` | Existing hub VNet resource ID | - | Yes |
| `parentManagementGroupId` | Parent management group | - | Yes |
| `ipamPoolPrefix` | IPAM pool CIDR block | - | Yes |

### Team Onboarding Configuration

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `teamName` | Team name for resources | - | Yes |
| `parentManagementGroupId` | Parent management group | - | Yes |
| `billingScope` | Billing scope for subscriptions | - | Yes |
| `location` | Azure region | - | Yes |
| `ipamPoolId` | IPAM pool resource ID | - | Yes |
| `vnetSizeInBits` | VNet size (CIDR) | 24 | Yes |
| `environments` | Environment list | ["dev", "uat", "prod"] | No |

## 🔒 Security Features

### Role-Based Access Control (RBAC)

- **Network Contributor**: Network management permissions
- **Reader**: Read-only access for monitoring
- **Custom Roles**: Environment-specific permissions
- **Principal Assignment**: Support for users, groups, and service principals

### Network Security

- **Network Security Groups**: Default deny-all inbound rules
- **Azure Firewall**: Centralized traffic inspection
- **AVNM Security Admin Rules**: Global security policies
- **Private Endpoints**: Secure access to Azure services

### Encryption

- **Encryption at Rest**: Enabled for all storage resources
- **Encryption in Transit**: TLS 1.3 for all communications
- **Key Management**: Azure Key Vault integration
- **Secret Management**: Secure credential storage

## 📊 Monitoring and Alerting

### Log Analytics Workspace

- **Centralized Logging**: All resource logs collected
- **Query Language**: KQL for log analysis
- **Retention Policies**: Configurable log retention
- **Data Export**: Integration with external SIEM systems

### Application Insights

- **Application Performance Monitoring**: Request tracking
- **Dependency Monitoring**: External service calls
- **Exception Tracking**: Error analysis and alerting
- **Availability Monitoring**: Health checks and probes

### Alerts and Notifications

- **Budget Alerts**: Cost threshold notifications
- **Resource Health**: Service availability alerts
- **Security Alerts**: Threat detection notifications
- **Custom Alerts**: User-defined alert rules

## 💰 Cost Optimization

### Budget Management

- **Monthly Budgets**: Configurable spending limits
- **Threshold Alerts**: Multi-level budget notifications
- **Cost Analysis**: Detailed cost breakdowns
- **Chargeback**: Department and team cost allocation

### Auto-Shutdown

- **Non-Production**: Automatic shutdown for dev/test
- **Configurable Schedules**: Custom shutdown times
- **Timezone Support**: Multiple timezone support
- **Override Options**: Manual override capabilities

### Resource Tagging

- **Cost Center Tracking**: Department allocation
- **Environment Classification**: Dev/test/prod identification
- **Owner Assignment**: Resource ownership tracking
- **Automation Tags**: Auto-shutdown and management tags

## 🔄 Error Handling and Retry Logic

### Subscription Creation

- **Retry Mechanism**: Up to 3 retry attempts
- **Backoff Strategy**: Exponential backoff delays
- **Error Logging**: Detailed error reporting
- **Validation**: Pre-creation validation checks

### Resource Deployment

- **Dependency Management**: Proper resource ordering
- **Failure Recovery**: Automatic rollback on failure
- **State Management**: Deployment state tracking
- **Error Reporting**: Comprehensive error messages

## 🧪 Testing and Validation

### Pre-Deployment Validation

- **Parameter Validation**: Input parameter validation
- **Resource Existence**: Existing resource verification
- **Permission Checks**: Access permission validation
- **Quota Verification**: Azure quota availability

### Post-Deployment Testing

- **Connectivity Tests**: Network connectivity validation
- **Security Tests**: Security configuration verification
- **Performance Tests**: Resource performance validation
- **Compliance Tests**: Policy compliance checking

## 🛡️ Backup and Disaster Recovery

### Backup Strategy

- **Configuration Backup**: Infrastructure-as-code backup
- **State Management**: Deployment state preservation
- **Recovery Procedures**: Step-by-step recovery guides
- **Testing**: Regular disaster recovery testing

### Business Continuity

- **High Availability**: Multi-region deployment options
- **Failover**: Automatic failover capabilities
- **Data Replication**: Critical data replication
- **Recovery Time**: Documented recovery time objectives

## 📈 Performance Optimization

### Resource Sizing

- **Right-Sizing**: Optimal resource allocation
- **Auto-Scaling**: Dynamic resource scaling
- **Performance Monitoring**: Resource utilization tracking
- **Optimization Recommendations**: AI-powered optimization

### Network Optimization

- **Traffic Routing**: Optimal traffic paths
- **Load Balancing**: Distributed load handling
- **CDN Integration**: Content delivery optimization
- **Latency Reduction**: Network latency optimization

## 🚀 Deployment Patterns

### Environment Separation

- **Development**: Isolated development environment
- **Testing**: Dedicated testing infrastructure
- **Staging**: Production-like staging environment
- **Production**: High-availability production environment

### Deployment Strategies

- **Blue-Green**: Zero-downtime deployments
- **Canary**: Gradual rollout strategy
- **Rolling**: Incremental updates
- **Feature Flags**: Feature toggle management

## 🔧 Troubleshooting

### Common Issues

1. **Subscription Creation Fails**
   - Check billing scope permissions
   - Verify enrollment account access
   - Review quota limitations

2. **AVNM Deployment Errors**
   - Validate network manager scopes
   - Check management group hierarchy
   - Verify IPAM pool configuration

3. **Network Connectivity Issues**
   - Review network security groups
   - Check Azure Firewall rules
   - Validate routing configurations

### Diagnostic Tools

- **Azure Monitor**: Resource health monitoring
- **Network Watcher**: Network diagnostics
- **Log Analytics**: Log analysis and querying
- **Resource Graph**: Resource inventory queries

## 📚 Best Practices

### Infrastructure as Code

- **Version Control**: Git-based version control
- **Branching Strategy**: Feature branch workflow
- **Code Review**: Peer review process
- **Documentation**: Comprehensive documentation

### Security Best Practices

- **Least Privilege**: Minimal required permissions
- **Network Segmentation**: Proper network isolation
- **Regular Updates**: Security patch management
- **Compliance**: Regulatory compliance adherence

### Operational Excellence

- **Monitoring**: Comprehensive monitoring coverage
- **Alerting**: Proactive alert configuration
- **Automation**: Infrastructure automation
- **Documentation**: Up-to-date documentation

## 🤝 Contributing

### Development Workflow

1. Fork the repository
2. Create feature branch
3. Implement changes
4. Add tests and documentation
5. Submit pull request

### Code Standards

- **Bicep Guidelines**: Follow Bicep best practices
- **Naming Conventions**: Consistent naming patterns
- **Documentation**: Comprehensive code comments
- **Testing**: Adequate test coverage


## 🆘 Support

### Documentation

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure Virtual Network Manager](https://docs.microsoft.com/en-us/azure/virtual-network-manager/)
- [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/)

### Community

- [Azure Community](https://techcommunity.microsoft.com/t5/azure/ct-p/Azure)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/azure-bicep)
- [GitHub Issues](https://github.com/your-repo/issues)

### Professional Support

- Microsoft Premier Support
- Azure Professional Services
- Partner Network

## 🔄 Version History

### Version 1.0.0 (Current)

- Initial release with full enterprise features
- AVNM integration with IPAM
- Security and compliance features
- Cost optimization capabilities
- Comprehensive monitoring

### Roadmap

- **v1.1.0**: Multi-region support
- **v1.2.0**: Advanced security features
- **v1.3.0**: AI-powered optimization
- **v2.0.0**: Kubernetes integration

---

**Note**: This is a living document. Please refer to the latest documentation and release notes for the most up-to-date information.