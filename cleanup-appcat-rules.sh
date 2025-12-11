#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eo pipefail

trap exit SIGINT SIGTERM

################################################################################
# AppCAT Ruleset Cleanup Script
# Optimized for Spring Boot applications targeting Azure AKS on Linux
# Removes unnecessary rulesets to speed up assessments

################################################################################
# Default configuration
RULESETS_DIR="${HOME}/.appcat/rulesets"
################################################################################

__usage="
    -x  action to be executed.

Possible verbs are:
    cleanup        Remove unnecessary rulesets and optimize for Spring Boot.

Environment variables (with defaults):
    RULESETS_DIR=${RULESETS_DIR}
"

usage() {
  echo "usage: ${0##*/} [options]"
  echo "${__usage/[[:space:]]/}"
  exit 1
}

print_header() {
  echo ""
  echo "AppCAT Ruleset Cleanup"
  echo "========================================================"
  echo ""
  echo "Optimized for Spring Boot apps targeting Azure AKS/Linux"
  echo "Rulesets Directory: $RULESETS_DIR"
  echo ""
}

remove_ruleset_directories() {
  echo "Removing entire ruleset directories..."
  local _RULESETS="camel3 camel4 droolsjbpm eap6 eap7 eap8 eapxp eapxp6 fuse fuse-service-works hibernate jakarta-ee9 jws6 openliberty openjdk7 openjdk8 openjdk11 quarkus rhr os"

  for i in ${_RULESETS}; do
    rm -rf "${RULESETS_DIR}/${i}"
    echo "  Removed: ${i} ruleset directory"
  done
  echo ""
}

clean_azure_ruleset() {
  echo "Cleaning azure ruleset..."
  cd "${RULESETS_DIR}/azure" 2>/dev/null && rm -f \
    01-azure-aws-config.yaml \
    11-azure-tas-binding.yaml \
    12-eap-to-azure-appservice-datasource-driver.yaml \
    13-eap-to-azure-appservice-pom.yaml \
    14-jetty-to-azure-external-resources.yaml \
    22-tomcat-to-azure-external-resources.yaml \
    29-openliberty-database.yaml \
    30-openliberty-filesystem.yaml \
    31-openliberty-jms.yaml \
    32-openliberty-logging.yaml \
    34-jakartaee-version-upgrade.yaml
  echo "  Removed: AWS, EAP, Jetty, Tomcat, OpenLiberty, JakartaEE rules"
  echo ""
}

clean_cloud_readiness_ruleset() {
  echo "Cleaning cloud-readiness ruleset..."
  cd "${RULESETS_DIR}/cloud-readiness" 2>/dev/null && rm -f \
    02-java-corba.yaml \
    03-java-rmi.yaml \
    04-java-rpc.yaml \
    05-jca.yaml \
    06-jni-native-code.yaml \
    17-webform-auth.yaml \
    18-windows-registry.yaml
  echo "  Removed: CORBA, RMI, RPC, JCA, JNI, WebForm, Windows registry rules"
  echo ""
}

clean_technology_usage_ruleset() {
  echo "Cleaning technology-usage ruleset..."
  cd "${RULESETS_DIR}/technology-usage" 2>/dev/null && rm -f \
    18-jta-technology-usage.yaml \
    21-javaee-technology-usage.yaml \
    28-ejb-technology-usage.yaml \
    199-ejb.yaml \
    209-jta.yaml
  echo "  Removed: EJB, Java EE, JTA rules"
  echo ""
}

print_summary() {
  echo "Cleanup complete!"
  echo ""
  echo "Remaining rulesets optimized for:"
  echo "   - Spring Boot applications"
  echo "   - Azure AKS / Container Apps / App Service"
  echo "   - Linux environment"
  echo "   - Cloud-native patterns"
  echo ""

  # Count remaining files
  local _TOTAL_FILES
  _TOTAL_FILES=$(find "${RULESETS_DIR}" -type f -name "*.yaml" 2>/dev/null | wc -l)
  echo "Total ruleset files: ${_TOTAL_FILES}"
  echo ""

  # List remaining directories
  echo "Remaining ruleset directories:"
  ls -1d "${RULESETS_DIR}"/*/ 2>/dev/null | while read -r dir; do
    local _COUNT
    _COUNT=$(ls -1 "${dir}" 2>/dev/null | wc -l)
    printf "   %-25s: %3d files\n" "$(basename "${dir}")" "${_COUNT}"
  done
}

exec_case() {
  local _opt=$1

  case ${_opt} in
  cleanup)       do_cleanup ;;
  *)             usage ;;
  esac
  unset _opt
}

do_cleanup() {
  print_header
  remove_ruleset_directories
  clean_azure_ruleset
  clean_cloud_readiness_ruleset
  clean_technology_usage_ruleset
  print_summary
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
    # No arguments, run cleanup by default
    do_cleanup
    exit 0
  fi

  # process actions
  if [[ "${exec_flag}" == "true" ]]; then
    exec_case "${EXEC_OPT}"
  fi
}

main "$@"
exit 0
