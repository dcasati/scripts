#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eo pipefail

################################################################################
# AKS Custom Scheduler Configuration Script
# Configures custom scheduler profiles for AKS cluster

################################################################################
# Default configuration
LOCATION=${LOCATION:-eastus2}
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-aks}
CLUSTER_NAME=${CLUSTER_NAME:-aks-cluster}
KUBECONFIG=${KUBECONFIG:-${PWD}/cluster.config}
################################################################################
trap exit SIGINT SIGTERM

__usage="
    -x  action to be executed.

Possible verbs are:
    install            Deploy all resources (cluster, GPU pool, scheduler configs).
    delete             Delete AKS cluster and resource group.
    show               Show cluster and scheduler information.
    check-deps         Check if required dependencies are installed.

    Resource Management:

    register           Register required preview features.
    create-rg          Create resource group.
    create             Create or update AKS cluster.
    create-gpu-pool    Create GPU node pool with H100 VMs.
    get-credentials    Retrieve cluster credentials to local kubeconfig.

    Scheduler Configuration:

    config             Generate scheduler configuration files.
    apply              Apply scheduler configuration to cluster.

Environment variables (with defaults):
    LOCATION=${LOCATION}
    RESOURCE_GROUP=${RESOURCE_GROUP}
    CLUSTER_NAME=${CLUSTER_NAME}
    SCHEDULER_CONFIG=${SCHEDULER_CONFIG}
    KUBECONFIG=${KUBECONFIG}
"

usage() {
  echo "usage: ${0##*/} [options]"
  echo "${__usage/[[:space:]]/}"
  exit 1
}

print_header() {
  echo ""
  echo "AKS Custom Scheduler Configuration"
  echo "=========================================="
  echo ""
  echo "Location:        $LOCATION"
  echo "Resource Group:  $RESOURCE_GROUP"
  echo "Cluster Name:    $CLUSTER_NAME"
  echo "kubeconfig:      $KUBECONFIG"
  echo ""
}

log() {
  echo "[$(date +"%r")] $*"
}

check_dependencies() {
  log "Checking dependencies..."
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

register_features() {
  log "Registering preview features..."

  log "  Registering UserDefinedSchedulerConfigurationPreview feature"
  az feature register \
    --namespace "Microsoft.ContainerService" \
    --name "UserDefinedSchedulerConfigurationPreview"

  log "  Registering Microsoft.ContainerService provider"
  az provider register --namespace "Microsoft.ContainerService" --wait

  log "Preview features registered"
}

create_resource_group() {
  log "Creating resource group $RESOURCE_GROUP in $LOCATION"
  az group create --location "$LOCATION" --name "$RESOURCE_GROUP"
}

create_cluster() {
  log "Setting up AKS cluster with custom scheduler configuration enabled..."

  # Check if cluster already exists
  if az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log "Cluster $CLUSTER_NAME already exists, updating configuration..."
    az aks update \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CLUSTER_NAME" \
      --enable-upstream-kubescheduler-user-configuration
    log "AKS cluster updated successfully"
  else
    log "Creating new AKS cluster..."
    az aks create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CLUSTER_NAME" \
      --node-count 1 \
      --enable-upstream-kubescheduler-user-configuration \
      --generate-ssh-keys
    log "AKS cluster created successfully"
  fi
}

create_gpu_node_pool() {
  log "Creating GPU node pool with Standard_NC40ads_H100_v5 in zone 1..."

  az aks nodepool add \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$CLUSTER_NAME" \
    --name gpunp \
    --node-count 1 \
    --node-vm-size Standard_NC40ads_H100_v5 \
    --zones 1

  log "GPU node pool created successfully"
}

get_credentials() {
  log "Getting cluster credentials..."

  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --file "$KUBECONFIG" \
    --overwrite-existing

  log "Credentials written to $KUBECONFIG"
}

generate_scheduler_config() {
  log "Generating scheduler configuration files"

  cat <<EOF >bin-pack-cpu-scheduler.yaml
apiVersion: aks.azure.com/v1alpha1
kind: SchedulerConfiguration
metadata:
  name: upstream
spec:
  rawConfig: |
    apiVersion: kubescheduler.config.k8s.io/v1
    kind: KubeSchedulerConfiguration
    profiles:
    - schedulerName: node-binpacking-scheduler
      pluginConfig:
          - name: NodeResourcesFit
            args:
              scoringStrategy:
                type: MostAllocated
                resources:
                  - name: cpu
                    weight: 1
EOF

  cat <<EOF >pod-topology-spreader-scheduler.yaml
apiVersion: aks.azure.com/v1alpha1
kind: SchedulerConfiguration
metadata:
  name: upstream
spec:
  rawConfig: |
    apiVersion: kubescheduler.config.k8s.io/v1
    kind: KubeSchedulerConfiguration
    profiles:
    - schedulerName: pod-distribution-scheduler
      pluginConfig:
          - name: PodTopologySpread
            args:
              apiVersion: kubescheduler.config.k8s.io/v1
              kind: PodTopologySpreadArgs
              defaultingType: List
              defaultConstraints:
                - maxSkew: 1
                  topologyKey: topology.kubernetes.io/zone
                  whenUnsatisfiable: ScheduleAnyway
EOF

  cat <<EOF >bin-pack-gpu-scheduler.yaml
apiVersion: aks.azure.com/v1alpha1
kind: SchedulerConfiguration
metadata:
  name: upstream
spec:
  rawConfig: |
    apiVersion: kubescheduler.config.k8s.io/v1
    kind: KubeSchedulerConfiguration
    profiles:
    - schedulerName: gpu-node-binpacking-scheduler
      plugins:
        multiPoint:
          enabled:
            - name: ImageLocality
            - name: NodeResourcesFit
            - name: NodeResourcesBalancedAllocation
      pluginConfig:
      - name: NodeResourcesFit
        args:
          scoringStrategy:
            type: MostAllocated
            resources:
            - name: cpu
              weight: 1
            - name: nvidia.com/gpu
              weight: 3
      - name: NodeResourcesBalancedAllocation
        args:
          resources:
          - name: nvidia.com/gpu
            weight: 1
EOF

  log "Configuration file generated successfully"
}

apply_scheduler_config() {
  log "Applying scheduler configuration to cluster..."

  if [ ! -f "$SCHEDULER_CONFIG" ]; then
    log "Configuration file $SCHEDULER_CONFIG not found. Generate it first with '-x config'"
    exit 1
  fi

  # Get cluster credentials
  log "Getting cluster credentials..."
  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

  # Apply configuration
  log "Applying configuration..."
  kubectl apply -f "$SCHEDULER_CONFIG"

  log "Scheduler configuration applied successfully"
}

do_show() {
  log "Getting cluster scheduler information..."

  if az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    CLUSTER_INFO=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --output json)

    echo ""
    echo "Cluster Information:"
    echo "==================="
    echo "Name: $CLUSTER_NAME"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Kubernetes Version: $(echo "$CLUSTER_INFO" | jq -r '.kubernetesVersion')"
    echo "Provisioning State: $(echo "$CLUSTER_INFO" | jq -r '.provisioningState')"
    echo ""

    # Get cluster credentials if not already set
    az aks get-credentials \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CLUSTER_NAME" \
      --overwrite-existing >/dev/null 2>&1

    # Show scheduler configurations if available
    echo "Scheduler Configurations:"
    echo "========================"
    kubectl get schedulerconfigurations 2>/dev/null || log "No scheduler configurations found"
  else
    log "Cluster $CLUSTER_NAME not found in resource group $RESOURCE_GROUP"
    exit 1
  fi
}

do_delete() {
  log "Destroying AKS cluster and resource group..."

  # Delete the cluster
  if az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log "Deleting AKS cluster $CLUSTER_NAME"
    az aks delete --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --yes
  else
    log "Cluster $CLUSTER_NAME not found, skipping cluster deletion"
  fi

  # Delete the resource group
  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log "Deleting resource group $RESOURCE_GROUP"
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  else
    log "Resource group $RESOURCE_GROUP not found, skipping resource group deletion"
  fi

  log "Destruction completed"
}

exec_case() {
  local _opt=$1

  case ${_opt} in
  install)           do_install ;;
  delete)            do_delete ;;
  show)              do_show ;;
  check-deps)        check_dependencies ;;
  register)          register_features ;;
  create-rg)         create_resource_group ;;
  create)            create_cluster ;;
  create-gpu-pool)   create_gpu_node_pool ;;
  get-credentials)   get_credentials ;;
  config)            generate_scheduler_config ;;
  apply)             apply_scheduler_config ;;
  *)                 usage ;;
  esac
  unset _opt
}

do_install() {
  check_dependencies
  register_features
  create_resource_group
  create_cluster
  create_gpu_node_pool
  generate_scheduler_config
  apply_scheduler_config
  log ""
  log "AKS custom scheduler setup completed!"
  log "Run '$0 -x show' to get cluster scheduler information"
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
