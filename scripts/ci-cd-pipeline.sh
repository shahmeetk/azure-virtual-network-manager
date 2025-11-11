#!/bin/bash

# Azure Enterprise Bicep Infrastructure CI/CD Pipeline Script
# This script implements a complete CI/CD pipeline for Bicep deployments

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

# Environment configuration
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION="${LOCATION:-eastus}"
PREFIX="${PREFIX:-cdm}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"

# Pipeline stages
STAGE_VALIDATE="validate"
STAGE_TEST="test"
STAGE_DEPLOY_DEV="deploy-dev"
STAGE_DEPLOY_STAGE="deploy-stage"
STAGE_DEPLOY_PROD="deploy-prod"

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
Usage: $0 [OPTIONS] [STAGE]

Azure Enterprise Bicep Infrastructure CI/CD Pipeline

STAGES:
    $STAGE_VALIDATE     Validate all Bicep files and configurations
    $STAGE_TEST         Run deployment tests
    $STAGE_DEPLOY_DEV   Deploy to development environment
    $STAGE_DEPLOY_STAGE Deploy to staging environment
    $STAGE_DEPLOY_PROD  Deploy to production environment

OPTIONS:
    -e, --environment ENV       Target environment (dev, stage, prod)
    -l, --location LOCATION     Azure region for deployment
    -p, --prefix PREFIX         Resource name prefix
    -s, --subscription ID       Azure subscription ID
    --skip-validation           Skip validation stage
    --skip-tests               Skip testing stage
    --dry-run                  Perform dry run only
    -h, --help                 Show this help message

EXAMPLES:
    $0 validate
    $0 test
    $0 deploy-dev
    $0 -e prod deploy-prod
    $0 --dry-run deploy-stage

EOF
}

# Parse command line arguments
parse_arguments() {
    local stage_provided=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -p|--prefix)
                PREFIX="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            $STAGE_VALIDATE|$STAGE_TEST|$STAGE_DEPLOY_DEV|$STAGE_DEPLOY_STAGE|$STAGE_DEPLOY_PROD)
                STAGE="$1"
                stage_provided=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [ "$stage_provided" = false ]; then
        error "No stage provided"
        usage
        exit 1
    fi
}

# Set Azure subscription
set_subscription() {
    if [ -n "$SUBSCRIPTION_ID" ]; then
        log "Setting Azure subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi
    
    local current_subscription=$(az account show --query id -o tsv)
    log "Current subscription: $current_subscription"
}

# Validate environment configuration
validate_environment() {
    log "Validating environment configuration..."
    
    case "$ENVIRONMENT" in
        dev|stage|prod)
            success "Environment '$ENVIRONMENT' is valid"
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT. Must be one of: dev, stage, prod"
            exit 1
            ;;
    esac
    
    # Validate Azure CLI login
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Environment validation completed"
}

# Run validation stage
run_validation_stage() {
    log "Running validation stage..."
    
    if [ "${SKIP_VALIDATION:-false}" = true ]; then
        warning "Skipping validation stage"
        return 0
    fi
    
    # Run Bicep validation
    log "Running Bicep validation..."
    if ! "$SCRIPT_DIR/validate-bicep.sh"; then
        error "Bicep validation failed"
        exit 1
    fi
    
    # Validate parameter files
    log "Validating parameter files..."
    find "$ROOT_DIR" -name "*.parameters.json" -type f -exec jq empty {} \; || {
        error "Parameter file validation failed"
        exit 1
    }
    
    success "Validation stage completed"
}

# Run testing stage
run_testing_stage() {
    log "Running testing stage..."
    
    if [ "${SKIP_TESTS:-false}" = true ]; then
        warning "Skipping testing stage"
        return 0
    fi
    
    # Run deployment tests
    log "Running deployment tests..."
    if ! "$SCRIPT_DIR/test-deployment.sh" --location "$LOCATION" --prefix "$PREFIX" --environment "$ENVIRONMENT" --dry-run true; then
        error "Deployment testing failed"
        exit 1
    fi
    
    success "Testing stage completed"
}

# Deploy hub infrastructure
deploy_hub() {
    log "Deploying hub infrastructure..."
    
    local hub_dir="$ROOT_DIR/1-platform-deployment/hub"
    local template_file="$hub_dir/main.bicep"
    local parameter_file="$hub_dir/main.parameters.$ENVIRONMENT.json"
    
    # Use default parameter file if environment-specific doesn't exist
    if [ ! -f "$parameter_file" ]; then
        parameter_file="$hub_dir/main.parameters.json"
    fi
    
    # Create resource group
    local resource_group="${PREFIX}-${ENVIRONMENT}-hub-rg"
    log "Creating resource group: $resource_group"
    
    if [ "${DRY_RUN:-false}" = true ]; then
        log "DRY RUN: Would create resource group: $resource_group"
    else
        az group create --name "$resource_group" --location "$LOCATION" --tags Environment="$ENVIRONMENT" Purpose="Hub"
    fi
    
    # Deploy template
    local deployment_name="hub-$(date +%Y%m%d%H%M%S)"
    log "Deploying hub template: $deployment_name"
    
    if [ "${DRY_RUN:-false}" = true ]; then
        log "DRY RUN: Would deploy hub template"
        return 0
    fi
    
    az deployment group create \
        --name "$deployment_name" \
        --resource-group "$resource_group" \
        --template-file "$template_file" \
        --parameters "$parameter_file" \
        --parameters location="$LOCATION" prefix="$PREFIX" \
        --what-if-result-format "FullResourcePayloads" \
        --what-if-exclude-change-types "Ignore" "NoChange"
    
    success "Hub deployment completed"
}

# Deploy team onboarding
deploy_team_onboarding() {
    log "Deploying team onboarding infrastructure..."
    
    local team_dir="$ROOT_DIR/2-team-onboarding"
    local template_file="$team_dir/main.bicep"
    local parameter_file="$team_dir/main.parameters.$ENVIRONMENT.json"
    
    # Use default parameter file if environment-specific doesn't exist
    if [ ! -f "$parameter_file" ]; then
        parameter_file="$team_dir/main.parameters.json"
    fi
    
    # Create resource group
    local resource_group="${PREFIX}-${ENVIRONMENT}-team-rg"
    log "Creating resource group: $resource_group"
    
    if [ "${DRY_RUN:-false}" = true ]; then
        log "DRY RUN: Would create resource group: $resource_group"
    else
        az group create --name "$resource_group" --location "$LOCATION" --tags Environment="$ENVIRONMENT" Purpose="Team"
    fi
    
    # Deploy template
    local deployment_name="team-$(date +%Y%m%d%H%M%S)"
    log "Deploying team onboarding template: $deployment_name"
    
    if [ "${DRY_RUN:-false}" = true ]; then
        log "DRY RUN: Would deploy team onboarding template"
        return 0
    fi
    
    az deployment group create \
        --name "$deployment_name" \
        --resource-group "$resource_group" \
        --template-file "$template_file" \
        --parameters "$parameter_file" \
        --parameters location="$LOCATION" prefix="$PREFIX" \
        --what-if-result-format "FullResourcePayloads" \
        --what-if-exclude-change-types "Ignore" "NoChange"
    
    success "Team onboarding deployment completed"
}

# Run deployment to development
run_deploy_dev_stage() {
    log "Running development deployment stage..."
    
    deploy_hub
    deploy_team_onboarding
    
    success "Development deployment stage completed"
}

# Run deployment to staging
run_deploy_stage_stage() {
    log "Running staging deployment stage..."
    
    # Additional validation for staging
    if [ "$ENVIRONMENT" = "stage" ]; then
        log "Performing additional staging validation..."
        # Add staging-specific validations here
    fi
    
    deploy_hub
    deploy_team_onboarding
    
    success "Staging deployment stage completed"
}

# Run deployment to production
run_deploy_prod_stage() {
    log "Running production deployment stage..."
    
    # Additional validation for production
    if [ "$ENVIRONMENT" = "prod" ]; then
        log "Performing additional production validation..."
        
        # Require manual approval for production
        warning "Production deployment requires manual approval"
        read -p "Do you want to proceed with production deployment? (yes/no): " -r
        if [[ ! $REPLY =~ ^yes$ ]]; then
            error "Production deployment cancelled by user"
            exit 1
        fi
    fi
    
    deploy_hub
    deploy_team_onboarding
    
    success "Production deployment stage completed"
}

# Generate deployment report
generate_deployment_report() {
    local stage=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$ROOT_DIR/deployment-report-${stage}-${timestamp}.json"
    
    log "Generating deployment report: $report_file"
    
    cat > "$report_file" << EOF
{
  "stage": "$stage",
  "environment": "$ENVIRONMENT",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "subscription": "$(az account show --query id -o tsv)",
  "location": "$LOCATION",
  "prefix": "$PREFIX",
  "status": "completed",
  "dryRun": ${DRY_RUN:-false}
}
EOF
    
    success "Deployment report generated: $report_file"
}

# Main pipeline function
main() {
    log "Starting Azure Enterprise Bicep Infrastructure CI/CD Pipeline"
    log "Stage: $STAGE, Environment: $ENVIRONMENT"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Set Azure subscription
    set_subscription
    
    # Validate environment
    validate_environment
    
    # Execute pipeline stage
    case "$STAGE" in
        $STAGE_VALIDATE)
            run_validation_stage
            ;;
        $STAGE_TEST)
            run_testing_stage
            ;;
        $STAGE_DEPLOY_DEV)
            run_deploy_dev_stage
            ;;
        $STAGE_DEPLOY_STAGE)
            run_deploy_stage_stage
            ;;
        $STAGE_DEPLOY_PROD)
            run_deploy_prod_stage
            ;;
        *)
            error "Unknown stage: $STAGE"
            exit 1
            ;;
    esac
    
    # Generate deployment report
    generate_deployment_report "$STAGE"
    
    echo ""
    success "CI/CD Pipeline completed successfully!"
    log "Stage: $STAGE, Environment: $ENVIRONMENT"
    log "Location: $LOCATION, Prefix: $PREFIX"
}

# Run main function
main "$@"