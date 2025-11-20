#!/usr/bin/env bash
set -euo pipefail
HUB_SUB="2c87d8e3-098f-43d2-83fe-8263a03bb909"
SPOKE_SUB="adb86055-a749-4b22-8d8b-4421b424256c"
LOCATION="eastus"
HUB_RG="avnm-test"
HUB_VNET="vnet-avnm-test"
HUB_VM="vm-hub-jump"
SPOKE_RG1="rg-test-development-1"
SPOKE_VNET1="vnet-rg-test-development-Development-1"
SPOKE_VM1="vm-spoke-dev-1"
SPOKE_RG2="rg-test-development-2"
SPOKE_VNET2="vnet-rg-test-development-Development-2"
SPOKE_VM2="vm-spoke-dev-2"
VM_SIZE="Standard_B2s"
USERNAME="admin-avnm"
PASSWORD="Smk@102905559"
TIMEOUT=900
OPERATION="all"
RESULTS="test-results.json"
ENVIRONMENT="Development"
TAGS="test-environment=true Environment=Development avnm-group=spokes"
WINDOWS_SKU="2022-Datacenter"
IMAGE_URN="MicrosoftWindowsServer:WindowsServer:2022-Datacenter:latest"
ENABLE_DIRECT=false
ENABLE_BASTION=false
SOURCE_IP=""
TEST_RG="rg-test-test-1"
TEST_VNET="vnet-rg-test-test-1"
TEST_VM="vm-spoke-test-1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hub-sub) HUB_SUB="$2"; shift 2;;
    --spoke-sub) SPOKE_SUB="$2"; shift 2;;
    --location) LOCATION="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --operation) OPERATION="$2"; shift 2;;
    --username) USERNAME="$2"; shift 2;;
    --password) PASSWORD="$2"; shift 2;;
    --enable-direct-access) ENABLE_DIRECT=true; shift 1;;
    --enable-bastion) ENABLE_BASTION=true; shift 1;;
    --environment) ENVIRONMENT="$2"; TAGS="test-environment=true Environment=$ENVIRONMENT avnm-group=spokes"; shift 2;;
    --source-ip) SOURCE_IP="$2"; shift 2;;
    *) echo "Unknown arg $1"; exit 1;;
  esac
done

# Enforce eastus for all connectivity tests
if [[ "$LOCATION" != "eastus" ]]; then
  echo "[Info] Forcing location to eastus for connectivity tests (was $LOCATION)"
  LOCATION="eastus"
fi
ensure_subnet() {
  local RG="$1" VNET="$2"
  if az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n default >/dev/null 2>&1; then
    echo "[Skip] Subnet 'default' already exists in $RG/$VNET"
    return 0
  fi
  local VNET_PREFIX
  VNET_PREFIX=$(az network vnet show -g "$RG" -n "$VNET" --query 'addressSpace.addressPrefixes[0]' -o tsv)
  if [[ -z "$VNET_PREFIX" ]]; then
    echo "Failed to read address space for VNet $VNET in RG $RG" >&2
    exit 1
  fi
  local CHILD_PREFIX
  CHILD_PREFIX=$(python3 - <<PY
import ipaddress
vnet_prefix = "$VNET_PREFIX"
net = ipaddress.ip_network(vnet_prefix)
new_prefix = min(net.prefixlen + 8, 28)
child = list(net.subnets(new_prefix=new_prefix))[0]
print(str(child))
PY
)
  echo "[Step] Creating subnet 'default' with prefix $CHILD_PREFIX in $RG/$VNET"
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n default --address-prefixes "$CHILD_PREFIX" >/dev/null
  echo "[OK] Subnet created"
}

ensure_bastion_subnet() {
  local RG="$1" VNET="$2"
  if az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n AzureBastionSubnet >/dev/null 2>&1; then
    echo "[Skip] Subnet 'AzureBastionSubnet' already exists in $RG/$VNET"
    return 0
  fi
  local VNET_PREFIX
  VNET_PREFIX=$(az network vnet show -g "$RG" -n "$VNET" --query 'addressSpace.addressPrefixes[0]' -o tsv)
  if [[ -z "$VNET_PREFIX" ]]; then
    echo "Failed to read address space for VNet $VNET in RG $RG" >&2
    exit 1
  fi
  local BASTION_PREFIX
  BASTION_PREFIX=$(python3 - <<PY
import ipaddress
net = ipaddress.ip_network("$VNET_PREFIX")
# Azure Bastion requires /26
new_prefix = 26 if net.prefixlen <= 26 else net.prefixlen
child = list(net.subnets(new_prefix=new_prefix))[0]
print(str(child))
PY
)
  echo "[Step] Creating 'AzureBastionSubnet' with prefix $BASTION_PREFIX in $RG/$VNET"
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n AzureBastionSubnet --address-prefixes "$BASTION_PREFIX" >/dev/null
  echo "[OK] AzureBastionSubnet created"
}

ensure_bastion() {
  local RG="$1" VNET="$2" BAS_NAME="bastion-${VNET}"
  ensure_bastion_subnet "$RG" "$VNET"
  if ! az network public-ip show -g "$RG" -n "${BAS_NAME}-pip" >/dev/null 2>&1; then
    echo "[Step] Creating Bastion Public IP ${BAS_NAME}-pip in $RG"
    az network public-ip create -g "$RG" -n "${BAS_NAME}-pip" --sku Standard --allocation-method Static --location "$LOCATION" --tags "$TAGS" >/dev/null
  fi
  if ! az network bastion show -g "$RG" -n "$BAS_NAME" >/dev/null 2>&1; then
    echo "[Step] Creating Bastion $BAS_NAME in $RG for $VNET"
    az network bastion create -g "$RG" -n "$BAS_NAME" --public-ip-address "${BAS_NAME}-pip" --vnet-name "$VNET" --location "$LOCATION" --sku Basic --tags "$TAGS" >/dev/null
    echo "[OK] Bastion created"
  else
    echo "[Skip] Bastion $BAS_NAME already exists in $RG"
  fi
}
vm_exists() { az vm show -g "$1" -n "$2" >/dev/null 2>&1; }
create_vm() {
  echo "[Step] Creating VM $2 in RG $1 (size=$VM_SIZE, image=$IMAGE_URN)"
  az vm create -g "$1" -n "$2" --image "$IMAGE_URN" --size "$VM_SIZE" --admin-username "$USERNAME" --admin-password "$PASSWORD" --vnet-name "$3" --subnet default --public-ip-address "" --authentication-type password --tags "$TAGS" --nsg "" >/dev/null
  echo "[OK] VM $2 created"
}

create_vm_with_tags() {
  local RG="$1" NAME="$2" VNET="$3" TAGS_ARG="$4"
  echo "[Step] Creating VM $NAME in RG $RG (size=$VM_SIZE, image=$IMAGE_URN)"
  az vm create -g "$RG" -n "$NAME" --image "$IMAGE_URN" --size "$VM_SIZE" --admin-username "$USERNAME" --admin-password "$PASSWORD" --vnet-name "$VNET" --subnet default --public-ip-address "" --authentication-type password --tags "$TAGS_ARG" --nsg "" >/dev/null
  echo "[OK] VM $NAME created"
}
create_vm_if_missing() { vm_exists "$1" "$2" || create_vm "$1" "$2" "$3"; }
vm_running() {
  local STATE
  STATE=$(az vm get-instance-view -g "$1" -n "$2" --query "instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]" -o tsv 2>/dev/null || echo "")
  [[ "$STATE" == "PowerState/running" ]]
}
ensure_vm_running() {
  if vm_exists "$1" "$2"; then
    if vm_running "$1" "$2"; then
      echo "[Skip] VM $2 already running in RG $1"
    else
      echo "[Step] Starting VM $2 in RG $1"
      az vm start -g "$1" -n "$2" >/dev/null
      echo "[OK] VM $2 started"
    fi
  fi
}

enable_icmp_windows_vm() {
  local RG="$1" VM="$2"
  echo "[Step] Enabling ICMP (Windows Firewall) on $VM in $RG"
  local PS_CMD
  PS_CMD="\$rule = Get-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)' -ErrorAction SilentlyContinue; if (\$null -ne \$rule) { Enable-NetFirewallRule -InputObject \$rule } else { \$existing = Get-NetFirewallRule -DisplayName 'Allow ICMPv4' -ErrorAction SilentlyContinue; if (\$null -eq \$existing) { New-NetFirewallRule -DisplayName 'Allow ICMPv4' -Protocol ICMPv4 -Direction Inbound -Action Allow -Enabled True -Profile Any } else { Enable-NetFirewallRule -InputObject \$existing } }"
  local SETTINGS
  SETTINGS=$(jq -n --arg c "powershell -ExecutionPolicy Unrestricted -Command $PS_CMD" '{commandToExecute:$c}')
  az vm extension set \
    --resource-group "$RG" \
    --vm-name "$VM" \
    --publisher Microsoft.Compute \
    --name CustomScriptExtension \
    --version 1.10 \
    --settings "$SETTINGS" >/dev/null
  echo "[OK] ICMP enabled on $VM"
}

ensure_disk_network_deny() {
  local RG="$1" VM="$2"
  local OS_DISK_ID DATA_DISKS
  OS_DISK_ID=$(az vm show -g "$RG" -n "$VM" --query 'storageProfile.osDisk.managedDisk.id' -o tsv)
  DATA_DISKS=$(az vm show -g "$RG" -n "$VM" --query 'storageProfile.dataDisks[].managedDisk.id' -o tsv | tr '\n' ' ')
  if [[ -n "$OS_DISK_ID" ]]; then
    az disk update --ids "$OS_DISK_ID" --network-access-policy DenyAll >/dev/null || true
  fi
  for D in $DATA_DISKS; do
    [[ -z "$D" ]] && continue
    az disk update --ids "$D" --network-access-policy DenyAll >/dev/null || true
  done
}

ensure_nsg() {
  local RG="$1" NSG_NAME="$2"
  az network nsg show -g "$RG" -n "$NSG_NAME" >/dev/null 2>&1 && return 0
  local SRC=${SOURCE_IP}
  if [[ -z "$SRC" ]]; then SRC=$(curl -s ifconfig.me 2>/dev/null || echo "0.0.0.0"); fi
  echo "[Step] Creating NSG $NSG_NAME in $RG with allow RDP from $SRC"
  az network nsg create -g "$RG" -n "$NSG_NAME" --tags "$TAGS" >/dev/null
  az network nsg rule create -g "$RG" --nsg-name "$NSG_NAME" -n allow-rdp --priority 100 \
    --access Allow --protocol Tcp --direction Inbound --source-address-prefixes "$SRC" --source-port-ranges '*' \
    --destination-address-prefixes '*' --destination-port-ranges 3389 >/dev/null
  echo "[OK] NSG $NSG_NAME ready"
}

attach_nsg_to_nic() {
  local RG="$1" NIC="$2" NSG="$3"
  echo "[Step] Attaching NSG $NSG to NIC $NIC in $RG"
  az network nic update -g "$RG" -n "$NIC" --network-security-group "$NSG" >/dev/null
  echo "[OK] NSG attached"
}

ensure_public_ip() {
  local RG="$1" VM="$2" NIC="$3" PIP_NAME="$4"
  local IPCFG
  IPCFG=$(az network nic ip-config list -g "$RG" --nic-name "$NIC" --query '[0].name' -o tsv)
  az network public-ip show -g "$RG" -n "$PIP_NAME" >/dev/null 2>&1 || az network public-ip create -g "$RG" -n "$PIP_NAME" --sku Standard --allocation-method Static --tags "$TAGS" >/dev/null
  echo "[Step] Associating PIP $PIP_NAME to NIC $NIC ($IPCFG)"
  az network nic ip-config update -g "$RG" --nic-name "$NIC" -n "$IPCFG" --public-ip-address "$PIP_NAME" >/dev/null
  echo "[OK] Public IP associated"
}
vm_id() { az vm show -g "$1" -n "$2" --query id -o tsv; }
nic_name() { az vm nic list -g "$1" --vm-name "$2" --query "[0].name" -o tsv; }
private_ip() { az vm list-ip-addresses -g "$1" -n "$2" --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv; }
subnet_route_table_json() {
  local RG="$1" VNET="$2"
  local RT_ID
  RT_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n default --query 'routeTable.id' -o tsv 2>/dev/null || echo "")
  if [[ -z "$RT_ID" ]]; then echo '{}' && return 0; fi
  az network route-table show --ids "$RT_ID" -o json
}
select_vm_size() {
  local candidates=("Standard_B1s" "Standard_B1ms" "Standard_B2s" "Standard_DS1_v2")
  for s in "${candidates[@]}"; do
    local available
    available=$(az vm list-skus --location "$LOCATION" --resource-type virtualMachines --query "[?name=='$s'] | length(@)" -o tsv || echo 0)
    if [[ "$available" == "1" ]]; then VM_SIZE="$s"; echo "[OK] Selected VM size: $VM_SIZE"; return 0; fi
  done
  echo "No supported VM size found in $LOCATION from candidates: ${candidates[*]}" >&2
  exit 1
}
select_windows_image() {
  local count
  count=$(az vm image list -l "$LOCATION" --publisher MicrosoftWindowsServer --offer WindowsServer --sku "$WINDOWS_SKU" --all --query "length(@)" -o tsv || echo 0)
  if [[ "$count" == "0" ]]; then WINDOWS_SKU="2019-Datacenter"; fi
  IMAGE_URN="MicrosoftWindowsServer:WindowsServer:${WINDOWS_SKU}:latest"
  echo "[OK] Selected Windows image: $IMAGE_URN"
}
provision() {
  echo "[Start] Provisioning test VMs in eastus"
  # select_vm_size
  # select_windows_image
  echo "[Context] Switching to hub subscription $HUB_SUB"
  az account set --subscription "$HUB_SUB"
  ensure_subnet "$HUB_RG" "$HUB_VNET"
  create_vm_if_missing "$HUB_RG" "$HUB_VM" "$HUB_VNET"; ensure_vm_running "$HUB_RG" "$HUB_VM"
  enable_icmp_windows_vm "$HUB_RG" "$HUB_VM"
  ensure_disk_network_deny "$HUB_RG" "$HUB_VM"
  echo "[Context] Switching to spoke subscription $SPOKE_SUB"
  az account set --subscription "$SPOKE_SUB"
  ensure_subnet "$SPOKE_RG1" "$SPOKE_VNET1"
  if [[ "$ENABLE_BASTION" == true ]]; then ensure_bastion "$SPOKE_RG1" "$SPOKE_VNET1"; fi
  create_vm_if_missing "$SPOKE_RG1" "$SPOKE_VM1" "$SPOKE_VNET1"; ensure_vm_running "$SPOKE_RG1" "$SPOKE_VM1"
  enable_icmp_windows_vm "$SPOKE_RG1" "$SPOKE_VM1"
  ensure_disk_network_deny "$SPOKE_RG1" "$SPOKE_VM1"
  if [[ "$ENABLE_DIRECT" == true ]]; then
    local NIC1
    NIC1=$(nic_name "$SPOKE_RG1" "$SPOKE_VM1")
    ensure_nsg "$SPOKE_RG1" nsg-test-access
    attach_nsg_to_nic "$SPOKE_RG1" "$NIC1" nsg-test-access
    ensure_public_ip "$SPOKE_RG1" "$SPOKE_VM1" "$NIC1" "${SPOKE_VM1}-pip"
  fi
  ensure_subnet "$SPOKE_RG2" "$SPOKE_VNET2"
  if [[ "$ENABLE_BASTION" == true ]]; then ensure_bastion "$SPOKE_RG2" "$SPOKE_VNET2"; fi
  create_vm_if_missing "$SPOKE_RG2" "$SPOKE_VM2" "$SPOKE_VNET2"; ensure_vm_running "$SPOKE_RG2" "$SPOKE_VM2"
  enable_icmp_windows_vm "$SPOKE_RG2" "$SPOKE_VM2"
  ensure_disk_network_deny "$SPOKE_RG2" "$SPOKE_VM2"
  if [[ "$ENABLE_DIRECT" == true ]]; then
    local NIC2
    NIC2=$(nic_name "$SPOKE_RG2" "$SPOKE_VM2")
    ensure_nsg "$SPOKE_RG2" nsg-test-access
    attach_nsg_to_nic "$SPOKE_RG2" "$NIC2" nsg-test-access
    ensure_public_ip "$SPOKE_RG2" "$SPOKE_VM2" "$NIC2" "${SPOKE_VM2}-pip"
  fi
  ensure_subnet "$TEST_RG" "$TEST_VNET"
  if [[ "$ENABLE_BASTION" == true ]]; then ensure_bastion "$TEST_RG" "$TEST_VNET"; fi
  create_vm_with_tags "$TEST_RG" "$TEST_VM" "$TEST_VNET" "test-environment=true Environment=Test avnm-group=spokes"; ensure_vm_running "$TEST_RG" "$TEST_VM"
  enable_icmp_windows_vm "$TEST_RG" "$TEST_VM"
  ensure_disk_network_deny "$TEST_RG" "$TEST_VM"
  if [[ "$ENABLE_DIRECT" == true ]]; then
    local NIC3
    NIC3=$(nic_name "$TEST_RG" "$TEST_VM")
    ensure_nsg "$TEST_RG" nsg-test-access
    attach_nsg_to_nic "$TEST_RG" "$NIC3" nsg-test-access
    ensure_public_ip "$TEST_RG" "$TEST_VM" "$NIC3" "${TEST_VM}-pip"
  fi
  echo "[Done] Provisioning complete"
}
collect_tests() {
  echo "[Start] Connectivity validation in eastus"
  az account set --subscription "$SPOKE_SUB"
  local SRC1 DST2 SRC2 DST1
  SRC1=$(vm_id "$SPOKE_RG1" "$SPOKE_VM1"); DST2=$(vm_id "$SPOKE_RG2" "$SPOKE_VM2")
  SRC2=$(vm_id "$SPOKE_RG2" "$SPOKE_VM2"); DST1=$(vm_id "$SPOKE_RG1" "$SPOKE_VM1")
  local R1 R2 T1_3389 T2_3389 T1_80 T2_80 PING_1_TO_2 PING_2_TO_1 DEST2_IP DEST1_IP
  R1=$(subnet_route_table_json "$SPOKE_RG1" "$SPOKE_VNET1"); R2=$(subnet_route_table_json "$SPOKE_RG2" "$SPOKE_VNET2")
  DEST2_IP=$(private_ip "$SPOKE_RG2" "$SPOKE_VM2"); DEST1_IP=$(private_ip "$SPOKE_RG1" "$SPOKE_VM1")
  local RT_TEST TEST_PIP TEST_BLOCKED_3389 TEST_BLOCKED_80
  RT_TEST=$(subnet_route_table_json "$TEST_RG" "$TEST_VNET")
  if [[ "$ENABLE_DIRECT" == true ]]; then
    local PIP1 PIP2
    PIP1=$(az network public-ip show -g "$SPOKE_RG1" -n "${SPOKE_VM1}-pip" --query ipAddress -o tsv 2>/dev/null || echo "")
    PIP2=$(az network public-ip show -g "$SPOKE_RG2" -n "${SPOKE_VM2}-pip" --query ipAddress -o tsv 2>/dev/null || echo "")
    TEST_PIP=$(az network public-ip show -g "$TEST_RG" -n "${TEST_VM}-pip" --query ipAddress -o tsv 2>/dev/null || echo "")
    if [[ -n "$PIP1" && -n "$PIP2" ]]; then
      echo "[Step] Local TCP tests to public IPs (nc)"
      T1_3389=$(nc -vz "$PIP2" 3389 >/dev/null 2>&1 && echo true || echo false)
      T2_3389=$(nc -vz "$PIP1" 3389 >/dev/null 2>&1 && echo true || echo false)
      T1_80=$(nc -vz "$PIP2" 80 >/dev/null 2>&1 && echo true || echo false)
      T2_80=$(nc -vz "$PIP1" 80 >/dev/null 2>&1 && echo true || echo false)
      echo "[Result] Local -> RG2 PIP TCP:3389 = $T1_3389"
      echo "[Result] Local -> RG1 PIP TCP:3389 = $T2_3389"
      echo "[Result] Local -> RG2 PIP TCP:80   = $T1_80"
      echo "[Result] Local -> RG1 PIP TCP:80   = $T2_80"
      PING_1_TO_2="local_ping_skipped"
      PING_2_TO_1="local_ping_skipped"
    else
      echo "[Warn] Public IPs not present; skipping local TCP tests"
      T1_3389="skipped"; T2_3389="skipped"; T1_80="skipped"; T2_80="skipped"
      PING_1_TO_2="skipped"; PING_2_TO_1="skipped"
    fi
    if [[ -n "$PIP1" && -n "$TEST_PIP" ]]; then
      TEST_BLOCKED_3389=$(nc -vz "$TEST_PIP" 3389 >/dev/null 2>&1 && echo false || echo true)
      TEST_BLOCKED_80=$(nc -vz "$TEST_PIP" 80 >/dev/null 2>&1 && echo false || echo true)
      echo "[Result] Local -> TEST PIP TCP:3389 blocked = $TEST_BLOCKED_3389"
      echo "[Result] Local -> TEST PIP TCP:80   blocked = $TEST_BLOCKED_80"
    else
      TEST_BLOCKED_3389="skipped"; TEST_BLOCKED_80="skipped"
    fi
  else
    echo "[Info] Direct access disabled; recording subnet route tables only"
    T1_3389="disabled"; T2_3389="disabled"; T1_80="disabled"; T2_80="disabled"
    PING_1_TO_2="disabled"; PING_2_TO_1="disabled"
  fi
  jq -n --argjson r1 "$R1" --argjson r2 "$R2" --argjson rt "$RT_TEST" --arg t13389 "$T1_3389" --arg t23389 "$T2_3389" --arg t180 "$T1_80" --arg t280 "$T2_80" --arg p12 "$PING_1_TO_2" --arg p21 "$PING_2_TO_1" --arg tb3389 "$TEST_BLOCKED_3389" --arg tb80 "$TEST_BLOCKED_80" '{routeTables:{rg1:$r1,rg2:$r2,test:$rt},connectivity:{rg1_to_rg2:{tcp3389:$t13389,tcp80:$t180,ping:$p12},rg2_to_rg1:{tcp3389:$t23389,tcp80:$t280,ping:$p21},dev_to_test:{tcp3389_blocked:$tb3389,tcp80_blocked:$tb80}}}' > "$RESULTS"
  echo "[Saved] Results written to $RESULTS"
  echo "[Done] Connectivity validation complete"
}
cleanup() {
  az account set --subscription "$SPOKE_SUB"; az vm delete -g "$SPOKE_RG1" -n "$SPOKE_VM1" --yes --no-wait; az vm delete -g "$SPOKE_RG2" -n "$SPOKE_VM2" --yes --no-wait;
  az account set --subscription "$HUB_SUB"; az vm delete -g "$HUB_RG" -n "$HUB_VM" --yes --no-wait;
}
timeout_run() { SECONDS=0; "$@"; if (( SECONDS > TIMEOUT )); then echo "Timeout exceeded"; exit 1; fi }
case "$OPERATION" in
  provision) timeout_run provision;;
  test) timeout_run collect_tests;;
  cleanup) cleanup;;
  all) timeout_run provision; timeout_run collect_tests; cleanup;;
  *) echo "Invalid operation"; exit 1;;
esac