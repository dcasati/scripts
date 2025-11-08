#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -e

# AKS Cluster Deployment Script
# Deploys a single-node AKS cluster with managed identity

################################################################################
# Default configuration
LOCATION=${LOCATION:-westus3}
RESOURCEGROUP=${RESOURCEGROUP:-rg-aks}
CLUSTER=${CLUSTER:-aks-cluster}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-1.33}
NODE_COUNT=${NODE_COUNT:-1}
KUBECONFIG=${KUBECONFIG:-${PWD}/cluster.config}
################################################################################

printHeader() {
  echo "AKS Cluster Deployment"
  echo "=========================================="
  echo "Kubernetes Version: $KUBERNETES_VERSION"
  echo "Node Count: $NODE_COUNT"
  echo "Location: $LOCATION"
  echo "Resource Group: $RESOURCEGROUP"
  echo ""
}

printUsage() {
  echo "usage: ${0##*/} [options]"
  echo ""
  echo "Available Commands:"
  echo "  -x install       Creates AKS cluster"
  echo "  -x destroy       Deletes AKS cluster and associated resources"
  echo "  -x show          Shows cluster information and credentials"
  echo "  -x check-deps    Checks if required dependencies are installed"
  echo ""
  echo "Environment variables (with defaults):"
  echo "  LOCATION=${LOCATION}"
  echo "  RESOURCEGROUP=${RESOURCEGROUP}"
  echo "  CLUSTER=${CLUSTER}"
  echo "  KUBERNETES_VERSION=${KUBERNETES_VERSION}"
  echo "  NODE_COUNT=${NODE_COUNT}"
  echo "  KUBECONFIG=${KUBECONFIG}"
  exit 1
}

log() {
  echo "[$(date +"%r")] $*"
}

checkDependencies() {
  log "Checking dependencies ..."
  local _NEEDED="az kubectl"
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

registerProviders() {
  log "Registering resource providers..."

  _PROVIDERS="Microsoft.Compute Microsoft.ContainerService Microsoft.Network"

  for provider in ${_PROVIDERS}; do
    log "  Registering $provider"
    az provider register -n "$provider" --wait
  done

  log "Resource providers registered"
}

createResourceGroup() {
  log "Creating resource group $RESOURCEGROUP in $LOCATION"
  az group create --location "$LOCATION" --name "$RESOURCEGROUP"
}

createVirtualNetwork() {
  log "Creating virtual network and subnet..."

  # Create virtual network
  az network vnet create \
    --resource-group "$RESOURCEGROUP" \
    --name aks-vnet \
    --address-prefixes 10.0.0.0/8

  # Create AKS subnet
  az network vnet subnet create \
    --resource-group "$RESOURCEGROUP" \
    --vnet-name aks-vnet \
    --name aks-subnet \
    --address-prefixes 10.1.0.0/16

  log "Virtual network created"
}

createCluster() {
  log "Creating AKS cluster with Kubernetes $KUBERNETES_VERSION..."

  # Get subnet ID
  SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$RESOURCEGROUP" \
    --vnet-name aks-vnet \
    --name aks-subnet \
    --query id -o tsv)

  # Create the cluster
  az aks create \
    --resource-group "$RESOURCEGROUP" \
    --name "$CLUSTER" \
    --kubernetes-version "$KUBERNETES_VERSION" \
    --node-count "$NODE_COUNT" \
    --enable-managed-identity \
    --vnet-subnet-id "$SUBNET_ID"

  log "AKS cluster created successfully"
}

getCredentials() {
  log "Getting cluster credentials..."

  az aks get-credentials \
    --resource-group "$RESOURCEGROUP" \
    --name "$CLUSTER" \
    --file "$KUBECONFIG" \
    --overwrite-existing

  log "Credentials written to $KUBECONFIG"
}

show() {
  log "Getting cluster information..."

  if az aks show --name "$CLUSTER" --resource-group "$RESOURCEGROUP" >/dev/null 2>&1; then
    CLUSTER_INFO=$(az aks show --name "$CLUSTER" --resource-group "$RESOURCEGROUP" --output json)

    echo ""
    echo "Cluster Information:"
    echo "==================="
    echo "Name: $CLUSTER"
    echo "Resource Group: $RESOURCEGROUP"
    echo "Location: $LOCATION"
    echo "Kubernetes Version: $(echo "$CLUSTER_INFO" | jq -r '.kubernetesVersion')"
    echo "Provisioning State: $(echo "$CLUSTER_INFO" | jq -r '.provisioningState')"
    echo "FQDN: $(echo "$CLUSTER_INFO" | jq -r '.fqdn')"
    echo ""
    echo "Node Pool Information:"
    echo "====================="
    az aks nodepool list --resource-group "$RESOURCEGROUP" --cluster-name "$CLUSTER" -o table
  else
    log "Cluster $CLUSTER not found in resource group $RESOURCEGROUP"
    exit 1
  fi
}

destroy() {
  log "Destroying AKS cluster and associated resources..."

  # Delete the cluster
  if az aks show --name "$CLUSTER" --resource-group "$RESOURCEGROUP" >/dev/null 2>&1; then
    log "Deleting AKS cluster $CLUSTER"
    az aks delete --name "$CLUSTER" --resource-group "$RESOURCEGROUP" --yes
  else
    log "Cluster $CLUSTER not found, skipping cluster deletion"
  fi

  # Delete the entire resource group
  log "Deleting resource group $RESOURCEGROUP"
  az group delete --name "$RESOURCEGROUP" --yes --no-wait

  log "Destruction completed"
}

exec_case() {
  local _opt=$1

  case ${_opt} in
    install) main ;;
    destroy) destroy ;;
    show) show ;;
    check-deps) checkDependencies ;;
    *) printUsage ;;
  esac
}

main() {
  checkDependencies
  registerProviders
  createResourceGroup
  createVirtualNetwork
  createCluster
  getCredentials

  log ""
  log "AKS cluster installation completed!"
  log "Run '$0 -x show' to get cluster information"
  log "Kubernetes version: $KUBERNETES_VERSION"
}

# Entry point
while getopts "x:" opt; do
  case $opt in
    x)
      exec_flag=true
      EXEC_OPT="${OPTARG}"
      ;;
    *) printUsage ;;
  esac
done
shift $((OPTIND - 1))

if [ $OPTIND = 1 ]; then
  printHeader
  printUsage
  exit 0
fi

if [[ "${exec_flag}" == "true" ]]; then
  exec_case "${EXEC_OPT}"
fi

exit 0
