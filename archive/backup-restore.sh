#!/bin/bash

# Azure Enterprise Bicep Infrastructure Backup and Restore Operations Script
# This script provides backup and restore operations for critical infrastructure components

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
PREFIX="cdm"
ENVIRONMENT="dev"
BACKUP_TYPE="full"
OPERATION="backup"
DRY_RUN=false
VERBOSE=false

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
Usage: $0 [OPTIONS] OPERATION

Azure Enterprise Bicep Infrastructure Backup and Restore Operations

OPERATIONS:
    backup              Perform backup operation
    restore             Perform restore operation
    list                List available backups
    status              Check backup status
    test-restore        Test restore operation
    cleanup             Cleanup old backups

OPTIONS:
    -l, --location LOCATION     Azure region (default: eastus)
    -p, --prefix PREFIX         Resource name prefix (default: cdm)
    -e, --environment ENV       Environment name (default: dev)
    -t, --backup-type TYPE      Backup type: full, incremental, differential (default: full)
    -r, --resource RESOURCE     Resource to backup/restore (avnm, ipam, all)
    -d, --dry-run               Perform dry run only
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

EXAMPLES:
    $0 backup --resource avnm
    $0 restore --resource ipam
    $0 list
    $0 status
    $0 test-restore --resource all
    $0 cleanup --days 30

EOF
}

# Parse command line arguments
parse_arguments() {
    local operation_provided=false
    
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
            -t|--backup-type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            -r|--resource)
                RESOURCE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            backup|restore|list|status|test-restore|cleanup)
                OPERATION="$1"
                operation_provided=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [ "$operation_provided" = false ]; then
        error "No operation provided"
        usage
        exit 1
    fi
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

# Get resource group names
get_resource_groups() {
    local hub_rg="${PREFIX}-${ENVIRONMENT}-hub-rg"
    local team_rg="${PREFIX}-${ENVIRONMENT}-team-rg"
    
    echo "$hub_rg $team_rg"
}

# Get Recovery Services Vault
get_recovery_vault() {
    local resource_group=$1
    local vault_name="${PREFIX}-rsv-${ENVIRONMENT}"
    
    if az resource show --resource-group "$resource_group" --name "$vault_name" --resource-type "Microsoft.RecoveryServices/vaults" &> /dev/null; then
        echo "$vault_name"
    else
        error "Recovery Services Vault not found: $vault_name"
        return 1
    fi
}

# Backup AVNM configuration
backup_avnm() {
    log "Backing up AVNM configuration..."
    
    local resource_groups=($(get_resource_groups))
    local hub_rg="${resource_groups[0]}"
    local vault_name
    
    vault_name=$(get_recovery_vault "$hub_rg")
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would backup AVNM configuration"
        return 0
    fi
    
    # Get AVNM resource
    local avnm_name="${PREFIX}-avnm-${ENVIRONMENT}"
    local avnm_resource=$(az resource show --resource-group "$hub_rg" --name "$avnm_name" --resource-type "Microsoft.Network/networkManagers" 2>/dev/null || echo "")
    
    if [ -z "$avnm_resource" ]; then
        error "AVNM resource not found: $avnm_name"
        return 1
    fi
    
    # Export AVNM configuration
    local backup_file="/tmp/avnm-backup-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S).json"
    
    log "Exporting AVNM configuration to: $backup_file"
    
    # Get network manager configuration
    az network manager show --resource-group "$hub_rg" --name "$avnm_name" > "$backup_file"
    
    # Get network manager configurations
    local configs=$(az network manager list-config --resource-group "$hub_rg" --network-manager-name "$avnm_name" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [ -n "$configs" ]; then
        echo "{"configurations": {"$avnm_name": {"configs": [