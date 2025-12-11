#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eo pipefail

trap exit SIGINT SIGTERM

################################################################################
# Hub-Spoke AKS with FreeBSD NVA Deployment Script
# Deploys a private AKS cluster with forced tunneling through a FreeBSD NVA running PF

################################################################################
# Default configuration
LOCATION=${LOCATION:-westus3}
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-aks-fw-test}
CLUSTER=${CLUSTER:-aks-fw-test}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-1.32}
NODE_COUNT=${NODE_COUNT:-1}
KUBECONFIG=${KUBECONFIG:-${PWD}/cluster.config}

# Network configuration
HUB_VNET_NAME=${HUB_VNET_NAME:-hub-vnet}
HUB_VNET_PREFIX=${HUB_VNET_PREFIX:-10.0.0.0/16}
NVA_SUBNET_PREFIX=${NVA_SUBNET_PREFIX:-10.0.2.0/24}

SPOKE_VNET_NAME=${SPOKE_VNET_NAME:-spoke-vnet}
SPOKE_VNET_PREFIX=${SPOKE_VNET_PREFIX:-10.1.0.0/16}
AKS_SUBNET_PREFIX=${AKS_SUBNET_PREFIX:-10.1.0.0/24}

# NVA configuration
NVA_NAME=${NVA_NAME:-freebsd-nva}
NVA_IMAGE=${NVA_IMAGE:-thefreebsdfoundation:freebsd-14_2:14_2-release-amd64-gen2-zfs:14.2.0}
NVA_SIZE=${NVA_SIZE:-Standard_B2ms}
################################################################################

__usage="
    -x  action to be executed.

Possible verbs are:
    install        Creates hub-spoke infrastructure with AKS and FreeBSD NVA.
    delete         Deletes all resources.
    show           Shows cluster and NVA information.
    check-deps     Checks if required dependencies are installed.
    test-icmp      Tests ICMP connectivity from AKS pod.

Environment variables (with defaults):
    LOCATION=${LOCATION}
    RESOURCE_GROUP=${RESOURCE_GROUP}
    CLUSTER=${CLUSTER}
    KUBERNETES_VERSION=${KUBERNETES_VERSION}
    NODE_COUNT=${NODE_COUNT}
    KUBECONFIG=${KUBECONFIG}
    HUB_VNET_NAME=${HUB_VNET_NAME}
    HUB_VNET_PREFIX=${HUB_VNET_PREFIX}
    NVA_SUBNET_PREFIX=${NVA_SUBNET_PREFIX}
    SPOKE_VNET_NAME=${SPOKE_VNET_NAME}
    SPOKE_VNET_PREFIX=${SPOKE_VNET_PREFIX}
    AKS_SUBNET_PREFIX=${AKS_SUBNET_PREFIX}
    NVA_NAME=${NVA_NAME}
"

usage() {
  echo "usage: ${0##*/} [options]"
  echo "${__usage/[[:space:]]/}"
  exit 1
}

print_header() {
  echo ""
  echo "Hub-Spoke AKS with FreeBSD NVA Deployment"
  echo "=========================================="
  echo ""
  echo "Kubernetes Version: $KUBERNETES_VERSION"
  echo "Node Count:         $NODE_COUNT"
  echo "Location:           $LOCATION"
  echo "Resource Group:     $RESOURCE_GROUP"
  echo "Hub VNet:           $HUB_VNET_NAME ($HUB_VNET_PREFIX)"
  echo "Spoke VNet:         $SPOKE_VNET_NAME ($SPOKE_VNET_PREFIX)"
  echo ""
}

log() {
  echo "[$(date +"%r")] $*"
}

check_dependencies() {
  log "Checking dependencies..."
  local _NEEDED="az kubectl ssh scp jq"
  local _DEP_FLAG=false

  for i in ${_NEEDED}; do
    if hash "$i" 2>/dev/null; then
      log "  $i: OK"
    else
      log "  $i: NOT FOUND"
      _DEP_FLAG=true
    fi
  done

  # Check Azure CLI version
  local AZ_VERSION
  AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
  if [[ $(echo "$AZ_VERSION 2.60.0" | tr " " "\n" | sort -V | head -n1) != "2.60.0" ]]; then
    log "  Azure CLI version $AZ_VERSION is too old. Minimum required: 2.60.0"
    _DEP_FLAG=true
  else
    log "  Azure CLI version: $AZ_VERSION (OK)"
  fi

  if [[ "${_DEP_FLAG}" == "true" ]]; then
    log "Dependencies missing. Please fix that before proceeding"
    exit 1
  fi

  log "All dependencies satisfied"
}

register_providers() {
  log "Registering resource providers..."

  _PROVIDERS="Microsoft.Compute Microsoft.ContainerService Microsoft.Network"

  for provider in ${_PROVIDERS}; do
    log "  Registering $provider"
    az provider register -n "$provider" --wait
  done

  log "Resource providers registered"
}

create_resource_group() { {
  log "Creating resource group $RESOURCE_GROUP in $LOCATION"
  az group create --location "$LOCATION" --name "$RESOURCE_GROUP" -o none
}

create_hub_vnet() { {
  log "Creating hub virtual network..."

  # Create hub VNet with NVA subnet
  az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$HUB_VNET_NAME" \
    --address-prefix "$HUB_VNET_PREFIX" \
    --subnet-name nva-subnet \
    --subnet-prefix "$NVA_SUBNET_PREFIX" \
    -o none

  log "Hub VNet created"
}

create_spoke_vnet() { {
  log "Creating spoke virtual network..."

  # Create spoke VNet with AKS subnet
  az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SPOKE_VNET_NAME" \
    --address-prefix "$SPOKE_VNET_PREFIX" \
    --subnet-name aks-subnet \
    --subnet-prefix "$AKS_SUBNET_PREFIX" \
    -o none

  log "Spoke VNet created"
}

create_vnet_peerings() {
  log "Creating VNet peerings..."

  # Get VNet IDs
  HUB_VNET_ID=$(az network vnet show -g "$RESOURCE_GROUP" -n "$HUB_VNET_NAME" --query id -o tsv)
  SPOKE_VNET_ID=$(az network vnet show -g "$RESOURCE_GROUP" -n "$SPOKE_VNET_NAME" --query id -o tsv)

  # Hub to Spoke peering
  az network vnet peering create \
    --resource-group "$RESOURCE_GROUP" \
    --name hub-to-spoke \
    --vnet-name "$HUB_VNET_NAME" \
    --remote-vnet "$SPOKE_VNET_ID" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    -o none

  # Spoke to Hub peering
  az network vnet peering create \
    --resource-group "$RESOURCE_GROUP" \
    --name spoke-to-hub \
    --vnet-name "$SPOKE_VNET_NAME" \
    --remote-vnet "$HUB_VNET_ID" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    -o none

  log "VNet peerings created"
}

accept_marketplace_terms() {
  log "Accepting FreeBSD marketplace terms..."

  az vm image terms accept \
    --publisher thefreebsdfoundation \
    --offer freebsd-14_2 \
    --plan 14_2-release-amd64-gen2-zfs \
    -o none 2>/dev/null || true

  log "Marketplace terms accepted"
}

create_nva() {
  log "Creating FreeBSD NVA..."

  # Create public IP for NVA
  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --name "${NVA_NAME}-pip" \
    --sku Standard \
    --allocation-method Static \
    -o none

  # Create NSG for NVA
  az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "${NVA_NAME}-nsg" \
    -o none

  # Allow SSH
  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "${NVA_NAME}-nsg" \
    --name allow-ssh \
    --priority 100 \
    --access Allow \
    --protocol Tcp \
    --destination-port-ranges 22 \
    -o none

  # Allow all from VNets
  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "${NVA_NAME}-nsg" \
    --name allow-vnet-inbound \
    --priority 200 \
    --access Allow \
    --protocol "*" \
    --direction Inbound \
    --source-address-prefixes "10.0.0.0/8" \
    --destination-port-ranges "*" \
    -o none

  # Create the FreeBSD VM
  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NVA_NAME" \
    --image "$NVA_IMAGE" \
    --size "$NVA_SIZE" \
    --vnet-name "$HUB_VNET_NAME" \
    --subnet nva-subnet \
    --public-ip-address "${NVA_NAME}-pip" \
    --admin-username azureuser \
    --generate-ssh-keys \
    --nsg "${NVA_NAME}-nsg" \
    -o none

  # Enable IP forwarding on NIC
  NIC_ID=$(az vm show -g "$RESOURCE_GROUP" -n "$NVA_NAME" --query "networkProfile.networkInterfaces[0].id" -o tsv)
  NIC_NAME=$(basename "$NIC_ID")
  az network nic update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC_NAME" \
    --ip-forwarding true \
    -o none

  log "FreeBSD NVA created"
}

configure_nva() {
  log "Configuring PF on FreeBSD NVA..."

  NVA_PIP=$(az network public-ip show -g "$RESOURCE_GROUP" -n "${NVA_NAME}-pip" --query ipAddress -o tsv)

  # Wait for VM to be ready
  sleep 30

  # Create PF configuration
  ssh -o StrictHostKeyChecking=no azureuser@"$NVA_PIP" "cat << 'EOF' | sudo tee /etc/pf.conf
# PF configuration for ICMP NAT
ext_if = \"hn0\"

# NAT all outbound traffic including ICMP
nat on \\\$ext_if from 10.0.0.0/8 to any -> (\\\$ext_if)

# Allow all traffic
pass all
EOF"

  # Enable IP forwarding and PF
  ssh azureuser@"$NVA_PIP" "sudo sysrc gateway_enable=YES && sudo sysrc pf_enable=YES && sudo sysctl net.inet.ip.forwarding=1"

  # Load PF rules
  ssh azureuser@"$NVA_PIP" "sudo kldload pf 2>/dev/null || true && sudo pfctl -f /etc/pf.conf && sudo pfctl -e 2>/dev/null || true"

  log "PF configured on FreeBSD NVA"
}

create_route_table() {
  log "Creating route table for forced tunneling..."

  # Get NVA private IP
  NVA_PRIVATE_IP=$(az vm show -g "$RESOURCE_GROUP" -n "$NVA_NAME" -d --query privateIps -o tsv)

  # Create route table
  az network route-table create \
    --resource-group "$RESOURCE_GROUP" \
    --name aks-rt \
    --disable-bgp-route-propagation true \
    -o none

  # Add default route to NVA
  az network route-table route create \
    --resource-group "$RESOURCE_GROUP" \
    --route-table-name aks-rt \
    --name default-route \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$NVA_PRIVATE_IP" \
    -o none

  # Associate route table with AKS subnet
  az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$SPOKE_VNET_NAME" \
    --name aks-subnet \
    --route-table aks-rt \
    -o none

  log "Route table created and associated"
}

create_aks_cluster() {
  log "Creating private AKS cluster..."

  # Get AKS subnet ID
  AKS_SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$SPOKE_VNET_NAME" \
    --name aks-subnet \
    --query id -o tsv)

  # Create the cluster
  az aks create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER" \
    --location "$LOCATION" \
    --kubernetes-version "$KUBERNETES_VERSION" \
    --node-count "$NODE_COUNT" \
    --vnet-subnet-id "$AKS_SUBNET_ID" \
    --network-plugin azure \
    --outbound-type userDefinedRouting \
    --enable-private-cluster \
    --generate-ssh-keys \
    --node-vm-size Standard_B2ms \
    -o none

  log "AKS cluster created"
}

link_private_dns_zone() {
  log "Linking private DNS zone to hub VNet..."

  # Get node resource group
  NODE_RG=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER" --query nodeResourceGroup -o tsv)

  # Get private DNS zone name
  DNS_ZONE=$(az network private-dns zone list -g "$NODE_RG" --query "[0].name" -o tsv)

  # Get hub VNet ID
  HUB_VNET_ID=$(az network vnet show -g "$RESOURCE_GROUP" -n "$HUB_VNET_NAME" --query id -o tsv)

  # Create DNS zone link
  az network private-dns link vnet create \
    --resource-group "$NODE_RG" \
    --zone-name "$DNS_ZONE" \
    --name hub-vnet-link \
    --virtual-network "$HUB_VNET_ID" \
    --registration-enabled false \
    -o none

  log "Private DNS zone linked to hub VNet"
}

get_credentials() {
  log "Getting cluster credentials..."

  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER" \
    --file "$KUBECONFIG" \
    --overwrite-existing

  log "Credentials written to $KUBECONFIG"
}

copy_kubeconfig_to_nva() {
  log "Copying kubeconfig to NVA..."

  NVA_PIP=$(az network public-ip show -g "$RESOURCE_GROUP" -n "${NVA_NAME}-pip" --query ipAddress -o tsv)
  scp -o StrictHostKeyChecking=no "$KUBECONFIG" azureuser@"$NVA_PIP":~/kubeconfig

  log "Kubeconfig copied to NVA at ~/kubeconfig"
}

create_test_pod() {
  log "Creating test pod..."

  az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER" \
    --command "kubectl run test-icmp --image=alpine --restart=Never --command -- sleep infinity" \
    2>/dev/null || true

  # Wait for pod to be ready
  sleep 10

  log "Test pod created"
}

do_test_icmp() {
  log "Testing ICMP connectivity from AKS pod..."

  echo ""
  echo "Ping test to 8.8.8.8:"
  echo "====================="
  az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER" \
    --command "kubectl exec test-icmp -- ping -c 3 8.8.8.8 2>/dev/null || echo 'Creating test pod first...'"

  echo ""
  echo "Checking outbound IP:"
  echo "====================="
  az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER" \
    --command "kubectl exec test-icmp -- wget -qO- ifconfig.me/ip 2>/dev/null"

  NVA_PIP=$(az network public-ip show -g "$RESOURCE_GROUP" -n "${NVA_NAME}-pip" --query ipAddress -o tsv)
  echo ""
  echo "Expected NVA public IP: $NVA_PIP"
}

do_show() {
  log "Getting infrastructure information..."

  echo ""
  echo "Resource Group: $RESOURCE_GROUP"
  echo "Location: $LOCATION"
  echo ""

  if az aks show --name "$CLUSTER" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "AKS Cluster Information:"
    echo "========================"
    az aks show --name "$CLUSTER" --resource-group "$RESOURCE_GROUP" \
      --query "{Name:name, State:provisioningState, K8sVersion:kubernetesVersion, PrivateCluster:apiServerAccessProfile.enablePrivateCluster}" \
      -o table
    echo ""
  fi

  if az vm show --name "$NVA_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    NVA_PIP=$(az network public-ip show -g "$RESOURCE_GROUP" -n "${NVA_NAME}-pip" --query ipAddress -o tsv)
    NVA_PRIVATE_IP=$(az vm show -g "$RESOURCE_GROUP" -n "$NVA_NAME" -d --query privateIps -o tsv)

    echo "FreeBSD NVA Information:"
    echo "========================"
    echo "Name: $NVA_NAME"
    echo "Public IP: $NVA_PIP"
    echo "Private IP: $NVA_PRIVATE_IP"
    echo "SSH: ssh azureuser@$NVA_PIP"
    echo ""
  fi

  echo "Network Configuration:"
  echo "======================"
  az network vnet list -g "$RESOURCE_GROUP" -o table
  echo ""

  echo "Route Table:"
  echo "============"
  az network route-table route list -g "$RESOURCE_GROUP" --route-table-name aks-rt -o table 2>/dev/null || echo "No route table found"
}

do_delete() {
  log "Destroying all resources..."

  # Delete the resource group
  log "Deleting resource group $RESOURCE_GROUP"
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait

  log "Destruction initiated (running in background)"
}

exec_case() {
  local _opt=$1

  case ${_opt} in
  install)       do_install ;;
  delete)        do_delete ;;
  show)          do_show ;;
  check-deps)    check_dependencies ;;
  test-icmp)     do_test_icmp ;;
  *)             usage ;;
  esac
  unset _opt
}

do_install() {
  check_dependencies
  register_providers
  create_resource_group
  create_hub_vnet
  create_spoke_vnet
  create_vnet_peerings
  accept_marketplace_terms
  create_nva
  configure_nva
  create_route_table
  create_aks_cluster
  link_private_dns_zone
  get_credentials
  copy_kubeconfig_to_nva
  create_test_pod

  log ""
  log "Hub-Spoke AKS with FreeBSD NVA installation completed!"
  log "Run '$0 -x show' to get infrastructure information"
  log "Run '$0 -x test-icmp' to test ICMP connectivity"
}

################################################################################
# Entry point
main() {
  while getopts "x:" opt; do
    case $opt in
      x)
        exec_flag=true
        EXEC_OPT="${OPTARG}"
        ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))

  if [ $OPTIND = 1 ]; then
    print_header
    usage
    exit 0
  fi

  # process actions
  if [[ "${exec_flag}" == "true" ]]; then
    exec_case "${EXEC_OPT}"
  fi
}

main "$@"
exit 0
