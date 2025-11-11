#!/bin/bash

# Azure Enterprise Bicep Infrastructure Validation Script
# This script validates all Bicep files for syntax errors, best practices, and security issues

set -euo pipefail

# Initialize counters
syntax_issues=0
security_issues=0
convention_issues=0
dependency_issues=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

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

# Check if Azure CLI is installed
check_azure_cli() {
    log "Checking Azure CLI installation..."
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    success "Azure CLI is installed"
}

# Check if Bicep CLI is installed
check_bicep_cli() {
    log "Checking Bicep CLI installation..."
    if ! command -v bicep &> /dev/null; then
        error "Bicep CLI is not installed. Installing..."
        az bicep install
    fi
    success "Bicep CLI is available"
}

# Validate individual Bicep file
validate_bicep_file() {
    local file="$1"
    local filename=$(basename "$file")
    
    log "Processing file: $file"
    
    # Bicep syntax validation
    log "Validating Bicep file: $file"
    if ! bicep build "$file" &> /dev/null; then
        error "Bicep syntax validation failed for: $file"
        syntax_issues=$((syntax_issues + 1))
    else
        success "Bicep syntax validation passed for: $file"
    fi
    
    # Security best practices validation
    log "Validating security best practices for: $file"
    if ! validate_security_best_practices "$file"; then
        security_issues=$((security_issues + 1))
    else
        success "Security best practices validation passed for: $file"
    fi
    
    # Parameter validation
    log "Validating parameters for: $file"
    if ! validate_parameter_conventions "$file"; then
        convention_issues=$((convention_issues + 1))
    else
        success "Parameter validation passed for: $file"
    fi
    
    # Resource dependencies validation
    log "Validating resource dependencies for: $file"
    if ! validate_dependencies "$file"; then
        dependency_issues=$((dependency_issues + 1))
    else
        success "Resource dependencies validation passed for: $file"
    fi
}

# Validate Bicep file security best practices
validate_security_best_practices() {
    local file=$1
    log "Validating security best practices for: $file"
    
    local issues=0
    
    # Check for hardcoded secrets or passwords
    if grep -i "password\|secret\|key" "$file" | grep -v "param\|var\|output" | grep -q "="; then
        warning "Potential hardcoded secret found in: $file"
        issues=$((issues + 1))
    fi
    
    # Check for proper parameter validation
    if ! grep -q "@minLength\|@maxLength\|@secure\|@allowed" "$file"; then
        warning "Missing parameter validation decorators in: $file"
        issues=$((issues + 1))
    fi
    
    # Check for RBAC configurations
    if grep -q "Microsoft.Authorization/roleAssignments" "$file"; then
        if ! grep -q "principalType\|roleDefinitionIdOrName" "$file"; then
            warning "RBAC configuration might be incomplete in: $file"
            issues=$((issues + 1))
        fi
    fi
    
    # Check for network security configurations
    if grep -q "Microsoft.Network/networkSecurityGroups\|Microsoft.Network/firewallPolicies" "$file"; then
        if ! grep -q "securityRules\|ruleCollections" "$file"; then
            warning "Network security configuration might be incomplete in: $file"
            issues=$((issues + 1))
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        success "Security best practices validation passed for: $file"
    else
        warning "Found $issues security best practice issues in: $file"
    fi
    
    return $issues
}

# Validate parameter usage and naming conventions
validate_parameter_conventions() {
    local file=$1
    log "Validating parameter conventions for: $file"
    
    local issues=0
    
    # Check for camelCase parameter names
    if grep -q "param [A-Z]" "$file"; then
        warning "Parameter names should use camelCase in: $file"
        issues=$((issues + 1))
    fi
    
    # Check for consistent naming patterns
    if grep -q "param.*name" "$file" && ! grep -q "param.*Name" "$file"; then
        if grep -q "param.*prefix" "$file" && grep -q "param.*Prefix" "$file"; then
            warning "Inconsistent naming convention for name/prefix parameters in: $file"
            issues=$((issues + 1))
        fi
    fi
    
    # Check for proper parameter descriptions
    if grep -q "param" "$file" && ! grep -A1 "param" "$file" | grep -q "@description"; then
        warning "Missing parameter descriptions in: $file"
        issues=$((issues + 1))
    fi
    
    if [ $issues -eq 0 ]; then
        success "Parameter conventions validation passed for: $file"
    else
        warning "Found $issues parameter convention issues in: $file"
    fi
    
    return $issues
}

# Validate resource dependencies
validate_dependencies() {
    local file=$1
    log "Validating resource dependencies for: $file"
    
    local issues=0
    
    # Check for proper dependsOn usage
    if grep -q "dependsOn" "$file"; then
        if ! grep -q "parent\|scope" "$file"; then
            warning "Consider using parent or scope instead of dependsOn in: $file"
            issues=$((issues + 1))
        fi
    fi
    
    # Check for circular dependencies (basic check)
    if grep -A5 -B5 "dependsOn" "$file" | grep -q "reference\|resourceId"; then
        warning "Potential circular dependency detected in: $file"
        issues=$((issues + 1))
    fi
    
    if [ $issues -eq 0 ]; then
        success "Dependencies validation passed for: $file"
    else
        warning "Found $issues dependency issues in: $file"
    fi
    
    return $issues
}

# Main validation function
main() {
    log "Starting Azure Enterprise Bicep Infrastructure validation..."
    
    # Check prerequisites
    check_azure_cli
    check_bicep_cli
    
    # Find all Bicep files
    log "Finding all Bicep files..."
    
    # Use a while-read loop with null-delimited find output to handle spaces in filenames
    bicep_files=()
    while IFS= read -r -d '' file; do
        bicep_files+=("$file")
    done < <(find "$ROOT_DIR" -name "*.bicep" -type f -print0 | sort -z)
    
    if [ ${#bicep_files[@]} -eq 0 ]; then
        error "No Bicep files found in the repository"
        exit 1
    fi
    
    success "Found ${#bicep_files[@]} Bicep files"
    
    # Validation results
    local syntax_errors=0
    local security_issues=0
    local convention_issues=0
    local dependency_issues=0
    
    # Validate each Bicep file
    for file in "${bicep_files[@]}"; do
        validate_bicep_file "$file" 2>&1 | while IFS= read -r line; do
            echo "$line"
        done
    done
    
    # Generate validation report
    generate_report() {
        log "Generating validation report..."
        
        echo ""
        echo "========================================="
        echo "AZURE ENTERPRISE BICEP VALIDATION REPORT"
        echo "========================================="
        echo ""
        echo "Summary:"
        echo "--------"
        echo "Total files validated: ${#bicep_files[@]}"
        echo "Syntax issues: $syntax_issues"
        echo "Security issues: $security_issues"
        echo "Convention issues: $convention_issues"
        echo "Dependency issues: $dependency_issues"
        echo ""
        
        local total_issues=$((syntax_issues + security_issues + convention_issues + dependency_issues))
        
        if [ $total_issues -eq 0 ]; then
            success "All validations passed! No issues found."
            return 0
        else
            error "Validation completed with $total_issues issues."
            
            if [ $syntax_issues -gt 0 ]; then
                echo "  - $syntax_issues syntax issues found"
            fi
            if [ $security_issues -gt 0 ]; then
                echo "  - $security_issues security issues found"
            fi
            if [ $convention_issues -gt 0 ]; then
                echo "  - $convention_issues convention issues found"
            fi
            if [ $dependency_issues -gt 0 ]; then
                echo "  - $dependency_issues dependency issues found"
            fi
            
            return 1
        fi
    }
    
    # Exit with appropriate code
    if [ $syntax_errors -gt 0 ]; then
        error "Validation failed due to syntax errors"
        exit 1
    elif [ $security_issues -gt 0 ] || [ $convention_issues -gt 0 ] || [ $dependency_issues -gt 0 ]; then
        warning "Validation completed with warnings"
        exit 0
    else
        success "All validations passed successfully!"
        exit 0
    fi
}

# Run main function
main "$@"