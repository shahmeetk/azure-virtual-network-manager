#!/bin/bash

# Azure Enterprise Bicep Infrastructure Deployment Testing Script
# This script performs comprehensive testing of Bicep deployments in a safe manner

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
LOCATION="eastus"
PREFIX="test"
ENVIRONMENT="test"
DRY_RUN=true
VALIDATION_ONLY=false

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Azure Enterprise Bicep Infrastructure Deployment Testing Script

OPTIONS:
    -l, --location LOCATION     Azure region for deployment (default: eastus)
    -p, --prefix PREFIX         Resource name prefix (default: test)
    -e, --environment ENV       Environment name (default: test)
    -d, --dry-run               Perform dry run only (default: true)
    -v, --validation-only       Run validation only, no deployment
    -h, --help                   Show this help message

EXAMPLES:
    $0 --location westus2 --prefix mytest --environment dev
    $0 --validation-only
    $0 --dry-run false --location eastus2

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -p|--prefix)
                PREFIX="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="$2"
                shift 2
                ;;
            -v|--validation-only)
                VALIDATION_ONLY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check Azure login status
check_azure_login() {
    log "Checking Azure login status..."
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    success "Azure login verified"
}

# Check Azure subscription
check_subscription() {
    log "Checking Azure subscription..."
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log "Current subscription: $subscription_name ($subscription_id)"
    
    # Check if subscription can create resources
    if ! az provider show --namespace Microsoft.Resources --query registrationState -o tsv | grep -q "Registered"; then
        warning "Microsoft.Resources provider not registered. Registering..."
        az provider register --namespace Microsoft.Resources
    fi
    
    success "Azure subscription check completed"
}

# Validate Bicep files
validate_bicep_files() {
    log "Validating Bicep files..."
    
    # Run the validation script
    if ! "$SCRIPT_DIR/validate-bicep.sh"; then
        error "Bicep validation failed"
        exit 1
    fi
    
    success "Bicep validation completed"
}

# Test parameter files
test_parameter_files() {
    log "Testing parameter files..."
    
    # Find all parameter files
    local param_files=()
    while IFS= read -r -d '' file; do
        param_files+=("$file")
    done < <(find "$ROOT_DIR" -name "*.parameters.json" -type f -print0)
    
    if [ ${#param_files[@]} -eq 0 ]; then
        warning "No parameter files found"
        return 0
    fi
    
    for param_file in "${param_files[@]}"; do
        log "Testing parameter file: $param_file"
        
        # Validate JSON syntax
        if ! jq empty "$param_file" &> /dev/null; then
            error "Invalid JSON syntax in parameter file: $param_file"
            return 1
        fi
        
        # Check for required parameters
        if ! jq -e '.parameters' "$param_file" &> /dev/null; then
            warning "No parameters section found in: $param_file"
        fi
        
        success "Parameter file validation passed: $param_file"
    done
}

# Test deployment what-if
test_what_if_deployment() {
    local template_file=$1
    local parameter_file=$2
    local resource_group=$3
    
    log "Testing what-if deployment for: $template_file"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would test what-if deployment for: $template_file"
        return 0
    fi
    
    # Create resource group if it doesn't exist
    if ! az group show --name "$resource_group" &> /dev/null; then
        log "Creating resource group: $resource_group"
        az group create --name "$resource_group" --location "$LOCATION"
    fi
    
    # Run what-if deployment
    local what_if_result
    if what_if_result=$(az deployment group what-if \
        --resource-group "$resource_group" \
        --template-file "$template_file" \
        --parameters "$parameter_file" \
        --no-pretty-print 2>&1); then
        
        log "What-if deployment completed successfully"
        
        # Analyze changes
        local changes=$(echo "$what_if_result" | jq -r '.properties.changes | length')
        log "Number of changes detected: $changes"
        
        if [ "$changes" -gt 0 ]; then
            warning "Deployment would make $changes changes"
            echo "$what_if_result" | jq -r '.properties.changes[] | "\(.changeType): \(.resourceId)"'
        fi
        
        success "What-if deployment test passed"
        return 0
    else
        error "What-if deployment failed: $what_if_result"
        return 1
    fi
}

# Test template deployment
test_template_deployment() {
    local template_file=$1
    local parameter_file=$2
    local resource_group=$3
    
    log "Testing template deployment for: $template_file"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would test deployment for: $template_file"
        return 0
    fi
    
    # Create resource group if it doesn't exist
    if ! az group show --name "$resource_group" &> /dev/null; then
        log "Creating resource group: $resource_group"
        az group create --name "$resource_group" --location "$LOCATION"
    fi
    
    # Run deployment
    local deployment_name="test-$(date +%Y%m%d%H%M%S)"
    local deployment_result
    
    if deployment_result=$(az deployment group create \
        --name "$deployment_name" \
        --resource-group "$resource_group" \
        --template-file "$template_file" \
        --parameters "$parameter_file" \
        --no-pretty-print 2>&1); then
        
        log "Deployment completed successfully"
        
        # Check deployment outputs
        local outputs=$(echo "$deployment_result" | jq -r '.properties.outputs // {}')
        if [ "$outputs" != "{}" ]; then
            log "Deployment outputs:"
            echo "$outputs" | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
        fi
        
        success "Template deployment test passed"
        return 0
    else
        error "Template deployment failed: $deployment_result"
        return 1
    fi
}

# Test resource cleanup
cleanup_test_resources() {
    local resource_group=$1
    
    log "Cleaning up test resources in: $resource_group"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would delete resource group: $resource_group"
        return 0
    fi
    
    # Delete resource group
    if az group delete --name "$resource_group" --yes --no-wait; then
        success "Resource cleanup initiated for: $resource_group"
    else
        warning "Failed to initiate resource cleanup for: $resource_group"
    fi
}

# Test hub deployment
test_hub_deployment() {
    log "Testing hub deployment..."
    
    local hub_dir="$ROOT_DIR/1-platform-deployment/hub"
    local template_file="$hub_dir/main.bicep"
    local parameter_file="$hub_dir/main.parameters.json"
    local resource_group="${PREFIX}-${ENVIRONMENT}-hub-test-rg"
    
    # Create test parameter file if it doesn't exist
    if [ ! -f "$parameter_file" ]; then
        log "Creating test parameter file for hub deployment..."
        cat > "$parameter_file" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "$LOCATION"
    },
    "prefix": {
      "value": "$PREFIX"
    },
    "hubVnetAddressPrefix": {
      "value": "10.0.0.0/16"
    },
    "hubFirewallName": {
      "value": "${PREFIX}-hub-fw"
    },
    "hubFirewallRgName": {
      "value": "${PREFIX}-hub-fw-rg"
    },
    "hubVnetId": {
      "value": ""
    },
    "parentManagementGroupId": {
      "value": ""
    },
    "ipamPoolPrefix": {
      "value": "10.0.0.0/8"
    },
    "networkContributorPrincipalIds": {
      "value": []
    },
    "readerPrincipalIds": {
      "value": []
    },
    "logAnalyticsWorkspaceId": {
      "value": ""
    },
    "enableAutoShutdown": {
      "value": false
    },
    "monthlyBudget": {
      "value": 1000
    },
    "budgetAlertThresholds": {
      "value": [50, 75, 90]
    }
  }
}
EOF
    fi
    
    # Test what-if deployment
    if ! test_what_if_deployment "$template_file" "$parameter_file" "$resource_group"; then
        error "Hub deployment what-if test failed"
        return 1
    fi
    
    # Test actual deployment (if not validation only)
    if [ "$VALIDATION_ONLY" = false ]; then
        if ! test_template_deployment "$template_file" "$parameter_file" "$resource_group"; then
            error "Hub deployment test failed"
            return 1
        fi
        
        # Cleanup
        cleanup_test_resources "$resource_group"
    fi
    
    success "Hub deployment test completed"
}

# Test team onboarding deployment
test_team_onboarding_deployment() {
    log "Testing team onboarding deployment..."
    
    local team_dir="$ROOT_DIR/2-team-onboarding"
    local template_file="$team_dir/main.bicep"
    local parameter_file="$team_dir/main.parameters.json"
    local resource_group="${PREFIX}-${ENVIRONMENT}-team-test-rg"
    
    # Create test parameter file if it doesn't exist
    if [ ! -f "$parameter_file" ]; then
        log "Creating test parameter file for team onboarding..."
        cat > "$parameter_file" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "teamName": {
      "value": "test-team"
    },
    "parentManagementGroupId": {
      "value": ""
    },
    "billingScope": {
      "value": ""
    },
    "location": {
      "value": "$LOCATION"
    },
    "environments": {
      "value": ["dev", "test"]
    },
    "ipamPoolId": {
      "value": ""
    },
    "maxRetries": {
      "value": 3
    },
    "retryDelaySeconds": {
      "value": 30
    },
    "enableLogging": {
      "value": true
    }
  }
}
EOF
    fi
    
    # Test what-if deployment
    if ! test_what_if_deployment "$template_file" "$parameter_file" "$resource_group"; then
        error "Team onboarding deployment what-if test failed"
        return 1
    fi
    
    # Test actual deployment (if not validation only)
    if [ "$VALIDATION_ONLY" = false ]; then
        if ! test_template_deployment "$template_file" "$parameter_file" "$resource_group"; then
            error "Team onboarding deployment test failed"
            return 1
        fi
        
        # Cleanup
        cleanup_test_resources "$resource_group"
    fi
    
    success "Team onboarding deployment test completed"
}

# Main testing function
main() {
    log "Starting Azure Enterprise Bicep Infrastructure deployment testing..."
    
    # Parse arguments
    parse_arguments "$@"
    
    log "Configuration:"
    log "  Location: $LOCATION"
    log "  Prefix: $PREFIX"
    log "  Environment: $ENVIRONMENT"
    log "  Dry Run: $DRY_RUN"
    log "  Validation Only: $VALIDATION_ONLY"
    
    # Check prerequisites
    check_azure_login
    check_subscription
    
    # Validate Bicep files
    validate_bicep_files
    
    # Test parameter files
    test_parameter_files
    
    # Test deployments
    test_hub_deployment
    test_team_onboarding_deployment
    
    echo ""
    success "All deployment tests completed successfully!"
}

# Run main function
main "$@"