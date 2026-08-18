#!/usr/bin/env bash
# Run all ECS utility tests
# Reports baseline compliance before refactoring

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}ECS Utils CLI 12-Factor Compliance Report${NC}"
echo -e "${BLUE}Date: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}================================================${NC}"

SCRIPTS_PASSED=0
SCRIPTS_FAILED=0
SCRIPTS_TOTAL=0

# Find all util scripts
find_util_scripts() {
  find "$SCRIPT_DIR/../utils" -name "*.sh" -type f 2> /dev/null || true
}

# Test a single script
test_script() {
  local script="$1"
  local script_name
  script_name=$(basename "$script")

  SCRIPTS_TOTAL=$((SCRIPTS_TOTAL + 1))

  echo -e "\n${YELLOW}Testing:${NC} $script_name"

  local checks=0
  local passed=0

  # Check 1: Has --help
  checks=$((checks + 1))
  if grep -q '\-\-help' "$script" 2> /dev/null; then
    passed=$((passed + 1))
  fi

  # Check 2: Has --version
  checks=$((checks + 1))
  if grep -q '\-\-version' "$script" 2> /dev/null; then
    passed=$((passed + 1))
  fi

  # Check 3: Has strict mode
  checks=$((checks + 1))
  if grep -q 'set -e' "$script" 2> /dev/null; then
    passed=$((passed + 1))
  fi

  # Check 4: Has proper shebang
  checks=$((checks + 1))
  if head -n1 "$script" | grep -qE '#!/usr/bin/env bash|#!/bin/bash' 2> /dev/null; then
    passed=$((passed + 1))
  fi

  # Check 5: --help works (only if it exists)
  if grep -q '\-\-help' "$script" 2> /dev/null; then
    checks=$((checks + 1))
    if "$script" --help > /dev/null 2>&1; then
      passed=$((passed + 1))
    fi
  fi

  # Report
  if [[ $passed -eq $checks ]]; then
    echo -e "  ${GREEN}✓${NC} $passed/$checks checks passed - COMPLIANT"
    SCRIPTS_PASSED=$((SCRIPTS_PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $passed/$checks checks passed - NEEDS REFACTORING"
    SCRIPTS_FAILED=$((SCRIPTS_FAILED + 1))
  fi
}

# Run all tests
mapfile -t SCRIPTS < <(find_util_scripts)

for script in "${SCRIPTS[@]}"; do
  if [[ -f "$script" ]]; then
    test_script "$script"
  fi
done

# Summary
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "Total Scripts Tested:  $SCRIPTS_TOTAL"
echo -e "Compliant:             ${GREEN}$SCRIPTS_PASSED${NC}"
echo -e "Need Refactoring:      ${RED}$SCRIPTS_FAILED${NC}"
