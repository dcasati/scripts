#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -e

# AppCAT Ruleset Cleanup Script
# Optimized for Spring Boot applications targeting Azure AKS on Linux
# Removes unnecessary rulesets to speed up assessments

################################################################################
RULESETS_DIR="${HOME}/.appcat/rulesets"
################################################################################

printHeader() {
  echo "AppCAT Ruleset Cleanup"
  echo "========================================================"
  echo "Optimized for Spring Boot apps targeting Azure AKS/Linux"
  echo ""
}

removeRulesetDirectories() {
  echo "Removing entire ruleset directories..."
  local _RULESETS="camel3 camel4 droolsjbpm eap6 eap7 eap8 eapxp eapxp6 fuse fuse-service-works hibernate jakarta-ee9 jws6 openliberty openjdk7 openjdk8 openjdk11 quarkus rhr os"
  
  for i in ${_RULESETS}; do
    rm -rf "${RULESETS_DIR}/${i}"
    echo "  Removed: ${i} ruleset directory"
  done
  echo ""
}

cleanAzureRuleset() {
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

cleanCloudReadinessRuleset() {
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

cleanTechnologyUsageRuleset() {
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

printSummary() {
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

main() {
  printHeader
  removeRulesetDirectories
  cleanAzureRuleset
  cleanCloudReadinessRuleset
  cleanTechnologyUsageRuleset
  printSummary
}

# entry point
main "$@"

exit 0
