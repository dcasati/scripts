# Bash Script Conventions and Style Guide

This document defines the coding standards and conventions for bash scripts in this project. All scripts should follow these guidelines for consistency and maintainability.

## Table of Contents
- [File Header](#file-header)
- [Script Structure](#script-structure)
- [Naming Conventions](#naming-conventions)
- [Configuration Variables](#configuration-variables)
- [Usage and Help](#usage-and-help)
- [Functions](#functions)
- [Error Handling](#error-handling)
- [Logging](#logging)
- [Command-Line Interface](#command-line-interface)
- [Code Style](#code-style)

---

## File Header

Every script must start with the following header:

```bash
#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eo pipefail

# Optional trap for signal handling
trap exit SIGINT SIGTERM
```

**Explanation:**
- `#!/usr/bin/env bash` - Portable shebang
- `# shfmt -i 2 -ci -w` - Formatter directive (2-space indent, switch case indent, write in-place)
- `set -Eo pipefail` - Exit on error, fail on pipe errors
- `trap exit SIGINT SIGTERM` - Clean exit on interrupt signals

---

## Script Structure

Scripts should follow this standard structure:

```bash
#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eo pipefail

trap exit SIGINT SIGTERM

################################################################################
# Script Title and Description
# Brief description of what the script does

################################################################################
# Default configuration
VARIABLE_NAME=${VARIABLE_NAME:-default_value}
ANOTHER_VAR=${ANOTHER_VAR:-default_value}
################################################################################

# Usage text
__usage="
    -x  action to be executed.

Possible verbs are:
    install        Description of install action.
    delete         Description of delete action.
    show           Description of show action.

Environment variables (with defaults):
    VARIABLE_NAME=${VARIABLE_NAME}
    ANOTHER_VAR=${ANOTHER_VAR}
"

usage() {
  echo "usage: ${0##*/} [options]"
  echo "${__usage/[[:space:]]/}"
  exit 1
}

print_header() {
  echo ""
  echo "Script Title"
  echo "=========================================="
  echo ""
  echo "Variable Name:   $VARIABLE_NAME"
  echo "Another Var:     $ANOTHER_VAR"
  echo ""
}

log() {
  echo "[$(date +"%r")] $*"
}

# Helper functions
helper_function() {
  log "Doing something..."
  # implementation
}

# Action functions
exec_case() {
  local _opt=$1

  case ${_opt} in
  install)       do_install ;;
  delete)        do_delete ;;
  show)          do_show ;;
  *)             usage ;;
  esac
  unset _opt
}

do_install() {
  log "Installing..."
  # implementation
}

do_delete() {
  log "Deleting..."
  # implementation
}

do_show() {
  log "Showing information..."
  # implementation
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
```

---

## Naming Conventions

### Variables
- **Global/Environment variables**: `UPPERCASE_WITH_UNDERSCORES`
  ```bash
  RESOURCE_GROUP=${RESOURCE_GROUP:-rg-default}
  CLUSTER_NAME=${CLUSTER_NAME:-cluster-default}
  ```

- **Local variables**: `lowercase_with_underscores` or `_prefixed`
  ```bash
  local _opt=$1
  local _DEP_FLAG=false
  local my_variable="value"
  ```

### Functions
- **Action functions**: `do_<action>` for main operations
  ```bash
  do_install() { ... }
  do_delete() { ... }
  do_show() { ... }
  ```

- **Helper functions**: `snake_case` or `camelCase` (pick one and be consistent)
  ```bash
  print_header() { ... }
  check_dependencies() { ... }
  ```

- **Utility functions**: lowercase, descriptive
  ```bash
  log() { ... }
  usage() { ... }
  ```

---

## Configuration Variables

All configuration should use environment variables with defaults:

```bash
################################################################################
# Default configuration
LOCATION=${LOCATION:-eastus2}
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-default}
CLUSTER_NAME=${CLUSTER_NAME:-aks-cluster}
CONFIG_FILE=${CONFIG_FILE:-config.yaml}
KUBECONFIG=${KUBECONFIG:-${PWD}/cluster.config}
################################################################################
```

**Pattern:** `VAR_NAME=${VAR_NAME:-default_value}`

This allows users to override via environment variables:
```bash
LOCATION=westus2 CLUSTER_NAME=my-cluster ./script.sh -x install
```

---

## Usage and Help

### Usage Text Format

```bash
__usage="
    -x  action to be executed.

Possible verbs are:
    install            Deploy all resources.
    delete             Delete all resources.
    show               Show resource information.
    check-deps         Check if required dependencies are installed.

    Optional Section Name:

    other-command      Description of other command.
    another-cmd        Description of another command.

Environment variables (with defaults):
    LOCATION=${LOCATION}
    RESOURCE_GROUP=${RESOURCE_GROUP}
    CLUSTER_NAME=${CLUSTER_NAME}
"

usage() {
  echo "usage: ${0##*/} [options]"
  echo "${__usage/[[:space:]]/}"
  exit 1
}
```

### Header Format

```bash
print_header() {
  echo ""
  echo "Script Title"
  echo "=========================================="
  echo ""
  echo "Location:        $LOCATION"
  echo "Resource Group:  $RESOURCE_GROUP"
  echo "Cluster Name:    $CLUSTER_NAME"
  echo "Config File:     $CONFIG_FILE"
  echo ""
}
```

**Key Points:**
- Align values using spaces for readability
- Include empty lines for visual separation
- Display current configuration values

---

## Functions

### Function Structure

```bash
function_name() {
  log "Starting function_name..."

  # Check prerequisites
  if [ ! -f "$REQUIRED_FILE" ]; then
    log "Error: Required file not found"
    exit 1
  fi

  # Main logic
  local result=$(some_command)

  # Validation
  if [ $? -ne 0 ]; then
    log "Command failed"
    exit 1
  fi

  log "function_name completed successfully"
}
```

### Dependency Checking Pattern

```bash
check_dependencies() {
  log "Checking dependencies..."
  local _NEEDED="tool1 tool2 tool3"
  local _DEP_FLAG=false

  for i in ${_NEEDED}; do
    if hash "$i" 2>/dev/null; then
      log "  $i: OK"
    else
      log "  $i: NOT FOUND"
      _DEP_FLAG=true
    fi
  done

  if [[ "${_DEP_FLAG}" == "true" ]]; then
    log "Dependencies missing. Please fix that before proceeding"
    exit 1
  fi

  log "All dependencies satisfied"
}
```

### Resource Existence Check Pattern

```bash
create_or_update_resource() {
  log "Setting up resource..."

  # Check if resource already exists
  if resource_exists "$RESOURCE_NAME"; then
    log "Resource already exists, updating..."
    update_resource
    log "Resource updated successfully"
  else
    log "Creating new resource..."
    create_resource
    log "Resource created successfully"
  fi
}
```

---

## Error Handling

### Exit on Error
Use `set -Eo pipefail` at the top of the script.

### Explicit Checks
```bash
if ! command_that_might_fail; then
  log "Error: Command failed"
  exit 1
fi
```

### Conditional Execution
```bash
# Check if resource exists before operating on it
if az resource show --name "$NAME" >/dev/null 2>&1; then
  log "Resource exists, proceeding..."
else
  log "Resource not found"
  exit 1
fi
```

---

## Logging

### Log Function

```bash
log() {
  echo "[$(date +"%r")] $*"
}
```

**Usage:**
```bash
log "Starting process..."
log "Processing item: $item_name"
log "  Substep completed"
log "Process completed successfully"
```

**Output Format:**
```
[10:30:45 AM] Starting process...
[10:30:46 AM] Processing item: example
[10:30:47 AM]   Substep completed
[10:30:48 AM] Process completed successfully
```

### Indentation for Substeps
```bash
log "Main operation..."
log "  Sub-operation 1"
log "  Sub-operation 2"
log "Main operation completed"
```

---

## Command-Line Interface

### Standard Pattern

```bash
exec_case() {
  local _opt=$1

  case ${_opt} in
  install)       do_install ;;
  delete)        do_delete ;;
  show)          do_show ;;
  check-deps)    check_dependencies ;;
  *)             usage ;;
  esac
  unset _opt
}

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
```

**Behavior:**
- No arguments: Show header and usage
- `-x <command>`: Execute the specified command

**Example usage:**
```bash
./script.sh                    # Show help
./script.sh -x check-deps      # Check dependencies
./script.sh -x install         # Run installation
```

---

## Code Style

### Indentation
- Use **2 spaces** for indentation (no tabs)
- Indent case statements

### Line Continuation
```bash
az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --node-count 1 \
  --generate-ssh-keys
```

### Quoting
- Always quote variables: `"$VARIABLE"`
- Use `$()` for command substitution, not backticks

### Conditionals
```bash
# Single line
if [ -f "$FILE" ]; then process_file; fi

# Multi-line
if [ -f "$FILE" ]; then
  process_file
  log "File processed"
fi

# Use [[ ]] for bash-specific tests
if [[ "${flag}" == "true" ]]; then
  do_something
fi
```

### Loops
```bash
# Iterate over list
for item in ${LIST}; do
  process "$item"
done

# Iterate over files
for file in *.txt; do
  process_file "$file"
done
```

### Heredocs
```bash
cat <<EOF >output.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CONFIG_NAME
data:
  key: $VALUE
EOF
```

### Comments
```bash
# Single line comment for brief explanation

# Multi-line comment for more complex explanations
# that need additional context or details
# about the following code block
```

---

## Complete Example

Here's a minimal but complete script following all conventions:

```bash
#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eo pipefail

trap exit SIGINT SIGTERM

################################################################################
# Resource Deployment Script
# Deploys and manages cloud resources

################################################################################
# Default configuration
LOCATION=${LOCATION:-eastus}
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-default}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-deployment-001}
################################################################################

__usage="
    -x  action to be executed.

Possible verbs are:
    install        Deploy all resources.
    delete         Delete all resources.
    show           Show deployment information.
    check-deps     Check required dependencies.

Environment variables (with defaults):
    LOCATION=${LOCATION}
    RESOURCE_GROUP=${RESOURCE_GROUP}
    DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
"

usage() {
  echo "usage: ${0##*/} [options]"
  echo "${__usage/[[:space:]]/}"
  exit 1
}

print_header() {
  echo ""
  echo "Resource Deployment"
  echo "=========================================="
  echo ""
  echo "Location:        $LOCATION"
  echo "Resource Group:  $RESOURCE_GROUP"
  echo "Deployment:      $DEPLOYMENT_NAME"
  echo ""
}

log() {
  echo "[$(date +"%r")] $*"
}

check_dependencies() {
  log "Checking dependencies..."
  local _NEEDED="az jq"
  local _DEP_FLAG=false

  for i in ${_NEEDED}; do
    if hash "$i" 2>/dev/null; then
      log "  $i: OK"
    else
      log "  $i: NOT FOUND"
      _DEP_FLAG=true
    fi
  done

  if [[ "${_DEP_FLAG}" == "true" ]]; then
    log "Dependencies missing. Please install them before proceeding"
    exit 1
  fi

  log "All dependencies satisfied"
}

create_resource_group() {
  log "Creating resource group $RESOURCE_GROUP in $LOCATION"
  az group create --location "$LOCATION" --name "$RESOURCE_GROUP"
}

deploy_resources() {
  log "Deploying resources..."
  
  if az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" >/dev/null 2>&1; then
    log "Deployment already exists, updating..."
  else
    log "Creating new deployment..."
  fi

  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --template-file template.json

  log "Deployment completed successfully"
}

do_show() {
  log "Getting deployment information..."

  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    DEPLOYMENT_INFO=$(az deployment group show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$DEPLOYMENT_NAME" \
      --output json)

    echo ""
    echo "Deployment Information:"
    echo "======================"
    echo "Name: $DEPLOYMENT_NAME"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Status: $(echo "$DEPLOYMENT_INFO" | jq -r '.properties.provisioningState')"
    echo ""
  else
    log "Resource group $RESOURCE_GROUP not found"
    exit 1
  fi
}

do_delete() {
  log "Deleting resources..."

  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log "Deleting resource group $RESOURCE_GROUP"
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    log "Deletion initiated"
  else
    log "Resource group not found, nothing to delete"
  fi
}

exec_case() {
  local _opt=$1

  case ${_opt} in
  install)       do_install ;;
  delete)        do_delete ;;
  show)          do_show ;;
  check-deps)    check_dependencies ;;
  *)             usage ;;
  esac
  unset _opt
}

do_install() {
  check_dependencies
  create_resource_group
  deploy_resources
  log ""
  log "Installation completed!"
  log "Run '$0 -x show' to view deployment details"
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
```

---

## Quick Reference Checklist

When creating a new script, ensure it has:

- [ ] Proper shebang: `#!/usr/bin/env bash`
- [ ] Format directive: `# shfmt -i 2 -ci -w`
- [ ] Error handling: `set -Eo pipefail`
- [ ] Signal trap: `trap exit SIGINT SIGTERM`
- [ ] Configuration section with defaults
- [ ] `__usage` variable with help text
- [ ] `usage()` function
- [ ] `print_header()` function
- [ ] `log()` function for output
- [ ] `check_dependencies()` if needed
- [ ] Action functions with `do_` prefix
- [ ] `exec_case()` for command routing
- [ ] `main()` function as entry point
- [ ] `main "$@"` at the end
- [ ] `exit 0` as final line

---

## Additional Notes

### Environment Variable Override
Users can override any configuration variable:
```bash
LOCATION=westus RESOURCE_GROUP=my-rg ./script.sh -x install
```

### Using direnv
For local development, create a `.envrc` file:
```bash
export LOCATION=eastus2
export RESOURCE_GROUP=my-test-rg
export CLUSTER_NAME=test-cluster
```

### Script Formatting
Format scripts using `shfmt`:
```bash
shfmt -i 2 -ci -w script.sh
```

---

**Last Updated:** December 2025  
**Maintainer:** Diego Casati