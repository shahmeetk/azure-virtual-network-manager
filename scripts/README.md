# Azure Enterprise Bicep Infrastructure Scripts

This directory contains automation scripts for validating, testing, and deploying the Azure Enterprise Bicep Infrastructure.

## Scripts Overview

Note: Connectivity auto-probe has been deprecated. Connectivity, Routing, and Security Admin are provisioned natively by `1-platform-deployment/hub/modules/avnm-configs.bicep` (api-version 2024-10-01). Use the unified policy module (`1-platform-deployment/hub/modules/avnm-policy.bicep`) to onboard tagged VNets at Subscription scope by default, or at Management Group scope via parameters.

### 1. `validate-bicep.sh`
Comprehensive validation script for Bicep files that checks:
- **Syntax validation**: Ensures all Bicep files compile correctly
- **Security best practices**: Identifies potential security issues
- **Parameter conventions**: Validates parameter naming and usage
- **Dependencies**: Checks for proper resource dependencies

**Usage:**
```bash
./validate-bicep.sh
```

**Features:**
- Color-coded output for easy identification of issues
- Detailed reporting of validation results
- Support for all Bicep files in the repository
- Security-focused validation rules

### 2. `test-deployment.sh`
Deployment testing script that safely tests Bicep deployments:
- **Parameter validation**: Tests all parameter files
- **What-if deployments**: Simulates deployments without making changes
- **Actual deployments**: Optionally deploys to test environments
- **Resource cleanup**: Automatically cleans up test resources

**Usage:**
```bash
# Dry run with validation only
./test-deployment.sh --validation-only

# Full deployment test
./test-deployment.sh --location eastus --prefix test --environment dev

# Custom configuration
./test-deployment.sh -l westus2 -p mytest -e staging --dry-run false
```

**Parameters:**
- `-l, --location`: Azure region (default: eastus)
- `-p, --prefix`: Resource name prefix (default: test)
- `-e, --environment`: Environment name (default: test)
- `-d, --dry-run`: Perform dry run only (default: true)
- `-v, --validation-only`: Run validation only, no deployment

### 3. `ci-cd-pipeline.sh`
Complete CI/CD pipeline implementation for automated deployments:
- **Multi-stage pipeline**: Validation → Testing → Deployment
- **Environment support**: Dev, Stage, Production environments
- **Safety features**: Dry-run mode, manual approval for production
- **Comprehensive reporting**: Detailed deployment reports

**Usage:**
```bash
# Run validation stage
./ci-cd-pipeline.sh validate

# Run testing stage
./ci-cd-pipeline.sh test

# Deploy to development
./ci-cd-pipeline.sh deploy-dev

# Deploy to production (requires manual approval)
./ci-cd-pipeline.sh -e prod deploy-prod

# Dry run for staging
./ci-cd-pipeline.sh -e stage --dry-run deploy-stage
```

**Pipeline Stages:**
1. **validate**: Validates all Bicep files and configurations
2. **test**: Runs deployment tests with what-if analysis
3. **deploy-dev**: Deploys to development environment
4. **deploy-stage**: Deploys to staging environment
5. **deploy-prod**: Deploys to production (with manual approval)

**Parameters:**
- `-e, --environment`: Target environment (dev, stage, prod)
- `-l, --location`: Azure region for deployment
- `-p, --prefix`: Resource name prefix
- `-s, --subscription`: Azure subscription ID
- `--skip-validation`: Skip validation stage
- `--skip-tests`: Skip testing stage
- `--dry-run`: Perform dry run only

### 4. `deploy-hub-and-sub-policy.sh`
Deploys the hub (RG scope) and then deploys the unified AVNM policy at Subscription scope by default, or at Management Group scope if specified.

Usage:
```bash
./deploy-hub-and-sub-policy.sh \
  --subscription <SUB_ID> \
  --resource-group <RG> \
  --location <LOCATION> \
  --params azure-enterprise-bicep/1-platform-deployment/hub/main.parameters.json \
  [--include-tag-name avnm-group] \
  [--include-tag-value spokes] \
  [--scope-type Subscription|ManagementGroup] \
  [--management-group-id <MG_ID>]
```

Parameters come from your parameter file for the hub; tag name/value can also be provided via CLI. The script reads `spokesNetworkGroupId` from the hub deployment outputs and then calls the unified policy module:

- Subscription scope (default): `1-platform-deployment/hub/modules/avnm-policy.bicep`
- Management Group scope: `1-platform-deployment/hub/mg-avnm-policy.bicep` (deploys directly at MG scope)

Deprecated scripts/modules moved to archive:
- `scripts/connectivity-autoprobe.sh` (deprecated)
- `1-platform-deployment/hub/modules/connectivity-autoprobe.bicep` (deprecated)
- `1-platform-deployment/hub/modules/avnm-configs-min.bicep` (deprecated)
- `1-platform-deployment/hub/modules/avnm-policy-sub.bicep` (deprecated)

### 5. `onboard-team.sh`
Onboards a team within the current subscription by creating (or reusing) a spoke Resource Group and deploying a spoke VNet carved from the AVNM IPAM pool.

Usage:
```bash
./onboard-team.sh \
  --subscription <CONTEXT_SUB_ID> \
  --location <LOCATION> \
  --params 2-team-onboarding/main.parameters.json \
  [--what-if] \
  [--name <DEPLOYMENT_NAME>]
```

Notes:
- Template paths are resolved relative to the directory of the provided `--params` file. For example, if `--params` points to `2-team-onboarding/main.parameters.json`, the script will use `2-team-onboarding/subscription-main.bicep`.
- The parameters file must provide: `teamName`, `location`, `environment`, `ipamPoolId`, `vnetSizeInBits`, `spokeResourceGroupName`.
- Ensure the Hub deployment has completed and you have the `ipamPoolId` from its outputs (see `1-platform-deployment/hub/main.bicep` outputs).
- Parameters are read from the JSON file. Required (managementGroup mode): `teamName`, `parentManagementGroupId`, `billingScope`, `location`, `ipamPoolId`. Required (subscription mode): `teamName`, `location`, `ipamPoolId`. Optional: `environments`, `vnetSizeInBits`, `maxRetries`, `retryDelaySeconds`, `enableLogging`, `includeTagName`, `includeTagValue`.

Outputs:
- In managementGroup mode: prints the new Team Management Group ID and a list of created subscriptions by environment.
- In subscription mode: prints completion and resources created in the current subscription.

### 6. `backup-restore.sh`
Comprehensive backup and restore operations script for critical infrastructure components.

**Usage:**
```bash
./backup-restore.sh [OPTIONS] OPERATION
```

**Operations:**
- `backup`: Perform backup operation
- `restore`: Perform restore operation
- `list`: List available backups
- `status`: Check backup status
- `test-restore`: Test restore operation
- `cleanup`: Cleanup old backups

**Parameters:**
- `-l, --location`: Azure region (default: eastus)
- `-p, --prefix`: Resource name prefix (default: cdm)
- `-e, --environment`: Environment name (default: dev)
- `-t, --backup-type`: Backup type: full, incremental, differential (default: full)
- `-r, --resource`: Resource to backup/restore (avnm, ipam, all)
- `-d, --dry-run`: Perform dry run only
- `-v, --verbose`: Enable verbose output
- `-h, --help`: Show help message

**Examples:**
```bash
# Backup AVNM configuration
./backup-restore.sh backup --resource avnm

# Backup IPAM Pool configuration
./backup-restore.sh backup --resource ipam

# List available backups
./backup-restore.sh list

# Check backup status
./backup-restore.sh status

# Test restore operation
./backup-restore.sh test-restore --resource all

# Cleanup backups older than 30 days
./backup-restore.sh cleanup --days 30
```

## Quick Start

1. **Validate your Bicep files:**
   ```bash
   ./validate-bicep.sh
   ```

2. **Test deployments (dry run):**
   ```bash
   ./test-deployment.sh --validation-only
   ```

3. **Run full CI/CD pipeline:**
   ```bash
   ./ci-cd-pipeline.sh validate
   ./ci-cd-pipeline.sh test
   ./ci-cd-pipeline.sh deploy-dev
   ```

## Prerequisites

- Azure CLI installed and logged in (`az login`)
- Bicep CLI installed (`az bicep install`)
- Appropriate Azure permissions for resource deployment
- Bash shell (Linux/macOS or WSL on Windows)

## Security Considerations

- Scripts include security validation for Bicep files
- Production deployments require manual approval
- Parameter files should not contain sensitive data
- Use Azure Key Vault for secrets management

## Error Handling

All scripts include comprehensive error handling:
- Exit on first error (set -e)
- Proper error messages with context
- Validation failure reporting
- Deployment rollback capabilities

## Integration with CI/CD Systems

These scripts can be integrated with various CI/CD systems:

### Azure DevOps
```yaml
- task: Bash@3
  inputs:
    filePath: 'scripts/ci-cd-pipeline.sh'
    arguments: 'validate'
```

### GitHub Actions
```yaml
- name: Validate Bicep
  run: ./scripts/ci-cd-pipeline.sh validate
```

### GitLab CI
```yaml
validate:
  script:
    - ./scripts/ci-cd-pipeline.sh validate
```

## Troubleshooting

### Common Issues

1. **Azure CLI not logged in:**
   ```bash
   az login
   ```

2. **Bicep CLI not installed:**
   ```bash
   az bicep install
   ```

3. **Permission errors:**
   - Ensure you have appropriate Azure RBAC permissions
   - Check subscription access and resource group permissions

4. **Parameter file issues:**
   - Validate JSON syntax: `jq empty parameters.json`
   - Check required parameters are provided

### Debug Mode

Run scripts with debug output:
```bash
bash -x ./validate-bicep.sh
```

## Contributing

When adding new scripts or modifying existing ones:
1. Follow the existing code style and patterns
2. Add comprehensive error handling
3. Include proper documentation
4. Test with different scenarios
5. Update this README with new features