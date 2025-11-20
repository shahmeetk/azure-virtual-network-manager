#!/usr/bin/env bash
set -euo pipefail

# ===================================================================================
# FILE:   cleanup-connectivity-test.sh
# DESC:   Deletes only the temporary resources created by test-connectivity.sh.
# USAGE:  ./scripts/cleanup-connectivity-test.sh [--hub-sub <SUB_ID>] [--spoke-sub <SUB_ID>]
# ===================================================================================

# --- Defaults (should match test-connectivity.sh) ---
HUB_SUB="2c87d8e3-098f-43d2-83fe-8263a03bb909"
SPOKE_SUB="adb86055-a749-4b22-8d8b-4421b424256c"
HUB_RG="avnm-test"
HUB_VM="vm-hub-jump"
SPOKE_RG1="rg-test-development-1"
SPOKE_VM1="vm-spoke-dev-1"
SPOKE_VNET1="vnet-rg-test-development-Development-1"
SPOKE_RG2="rg-test-development-2"
SPOKE_VM2="vm-spoke-dev-2"
SPOKE_VNET2="vnet-rg-test-development-Development-2"
DRY_RUN=false

# --- Functions ---
usage() {
  cat << EOF
Usage: $0 [--hub-sub <SUB_ID>] [--spoke-sub <SUB_ID>] [--dry-run]

Description:
  Deletes the specific test resources (VMs, NICs, Disks, Bastion) created by
  the 'test-connectivity.sh' script. If subscription IDs are not provided,
  it will use the currently active Azure CLI subscription.

Arguments:
  --hub-sub <SUB_ID>      (Optional) The subscription ID for the hub resources. Defaults to the current active subscription.
  --spoke-sub <SUB_ID>    (Optional) The subscription ID for the spoke resources. Defaults to the current active subscription.
  --dry-run               (Optional) Show what would be deleted without actually deleting anything.
  -h, --help              Show this help message.
EOF
}

delete_vm_and_deps() {
  local RG="$1" VM="$2"
  if ! az vm show -g "$RG" -n "$VM" --query "id" -o tsv >/dev/null 2>&1; then
    echo "[Skip] VM '$VM' not found in resource group '$RG'."
    return
  fi

  echo "[Info] Found VM '$VM'. Preparing to delete it and its associated NICs and Disks..."

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DryRun] Would delete VM: $VM (RG: $RG) with its OS Disk and NICs."
  else
    echo "Deleting VM: $VM and its associated resources..."
    # Use built-in flags to handle dependencies correctly. This command will wait for completion.
    az vm delete -g "$RG" -n "$VM" --yes --delete-os-disk --delete-nics
  fi
}

delete_bastion() {
  local RG="$1" VNET_NAME="$2"
  if [[ -z "$VNET_NAME" ]]; then
    echo "[Skip] VNet name not provided for Bastion deletion in RG '$RG'."
    return
  fi

  local BASTION_NAME="bastion-${VNET_NAME}"
  if ! az network bastion show -g "$RG" -n "$BASTION_NAME" --query "id" -o tsv >/dev/null 2>&1; then
    echo "[Skip] Bastion host '$BASTION_NAME' not found in RG '$RG'."
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DryRun] Would delete Bastion Host: $BASTION_NAME (RG: $RG)"
  else
    echo "Deleting Bastion Host: $BASTION_NAME..."
    # Remove --no-wait to ensure script waits for completion
    az network bastion delete -g "$RG" -n "$BASTION_NAME" || echo "[Warning] Failed to delete Bastion $BASTION_NAME."
  fi
}


# --- Argument Parsing & Validation ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hub-sub)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --hub-sub" >&2; usage; exit 1; fi
      HUB_SUB="$2"; shift 2;;
    --spoke-sub)
      if [[ -z "${2:-}" ]]; then echo "Error: Missing value for --spoke-sub" >&2; usage; exit 1; fi
      SPOKE_SUB="$2"; shift 2;;
    --dry-run)
      DRY_RUN=true; shift 1;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# --- Main Execution ---
echo "Starting cleanup of connectivity test resources..."

# Default to current subscription if not provided
if [[ -z "$HUB_SUB" ]]; then
  HUB_SUB=$(az account show --query id -o tsv)
  echo "[Info] --hub-sub not provided. Using current active subscription: $HUB_SUB"
fi
if [[ -z "$SPOKE_SUB" ]]; then
  SPOKE_SUB=$(az account show --query id -o tsv)
  echo "[Info] --spoke-sub not provided. Using current active subscription: $SPOKE_SUB"
fi

echo -e "\n[Cleanup] Processing Hub Subscription: $HUB_SUB"
az account set --subscription "$HUB_SUB"
delete_vm_and_deps "$HUB_RG" "$HUB_VM"

echo -e "\n[Cleanup] Processing Spoke Subscription: $SPOKE_SUB"
az account set --subscription "$SPOKE_SUB"
delete_vm_and_deps "$SPOKE_RG1" "$SPOKE_VM1"
delete_bastion "$SPOKE_RG1" "$SPOKE_VNET1"
delete_vm_and_deps "$SPOKE_RG2" "$SPOKE_VM2"
delete_bastion "$SPOKE_RG2" "$SPOKE_VNET2"

echo -e "\n[Done] Cleanup complete. Note: Deletions may still be in progress in Azure."
