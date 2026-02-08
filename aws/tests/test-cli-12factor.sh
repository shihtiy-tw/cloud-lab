#!/usr/bin/env bash
# CLI 12-Factor Test Framework
# Tests scripts for compliance with CLI 12-factor principles

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <script_path>

Test a script for CLI 12-factor compliance.

OPTIONS:
    --all                 Run all tests in tests/ directory
    --addons              Test all addon scripts
    --scenarios           Test all scenario scripts
    --verbose             Show detailed output
    --json                Output results as JSON
    -h, --help            Show this help message
    -v, --version         Show script version

TESTS PERFORMED:
    1. Script has --help flag
    2. --help exits with code 0
    3. Script has --version flag
    4. --version exits with code 0
    5. Invalid flag exits with code 1
    6. Script is executable
    7. Shebang is #!/usr/bin/env bash
    8. Uses set -euo pipefail

EXAMPLES:
    $(basename "$0") ./build.sh
    $(basename "$0") --all
    $(basename "$0") --addons --verbose
EOF
}

show_version() {
    echo "$(basename "$0") version ${SCRIPT_VERSION}"
}

# Logging
log_pass() { echo -e "  ${GREEN}✓${NC} $*"; ((TESTS_PASSED++)); ((TESTS_RUN++)); }
log_fail() { echo -e "  ${RED}✗${NC} $*"; ((TESTS_FAILED++)); ((TESTS_RUN++)); }
log_skip() { echo -e "  ${YELLOW}○${NC} $* (skipped)"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_header() { echo -e "\n${YELLOW}=== $* ===${NC}"; }

VERBOSE=false
JSON_OUTPUT=false

# Parse arguments
SCRIPTS_TO_TEST=()
TEST_MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            TEST_MODE="all"
            shift
            ;;
        --addons)
            TEST_MODE="addons"
            shift
            ;;
        --scenarios)
            TEST_MODE="scenarios"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            SCRIPTS_TO_TEST+=("$1")
            shift
            ;;
    esac
done

# Test functions
test_has_help() {
    local script="$1"
    if grep -q '\-\-help' "$script" 2>/dev/null; then
        log_pass "Has --help flag"
        return 0
    else
        log_fail "Missing --help flag"
        return 1
    fi
}

test_help_exits_zero() {
    local script="$1"
    if "$script" --help > /dev/null 2>&1; then
        log_pass "--help exits with code 0"
        return 0
    else
        log_fail "--help does not exit with code 0"
        return 1
    fi
}

test_has_version() {
    local script="$1"
    if grep -q '\-\-version' "$script" 2>/dev/null; then
        log_pass "Has --version flag"
        return 0
    else
        log_fail "Missing --version flag"
        return 1
    fi
}

test_version_exits_zero() {
    local script="$1"
    if "$script" --version > /dev/null 2>&1; then
        log_pass "--version exits with code 0"
        return 0
    else
        log_fail "--version does not exit with code 0"
        return 1
    fi
}

test_invalid_flag_exits_nonzero() {
    local script="$1"
    if ! "$script" --invalid-flag-that-doesnt-exist > /dev/null 2>&1; then
        log_pass "Invalid flag exits non-zero"
        return 0
    else
        log_fail "Invalid flag should exit non-zero"
        return 1
    fi
}

test_is_executable() {
    local script="$1"
    if [[ -x "$script" ]]; then
        log_pass "Script is executable"
        return 0
    else
        log_fail "Script is not executable"
        return 1
    fi
}

test_has_shebang() {
    local script="$1"
    local first_line
    first_line=$(head -n1 "$script")
    if [[ "$first_line" == "#!/usr/bin/env bash" ]] || [[ "$first_line" == "#!/bin/bash" ]]; then
        log_pass "Has proper shebang"
        return 0
    else
        log_fail "Missing or incorrect shebang (got: $first_line)"
        return 1
    fi
}

test_has_strict_mode() {
    local script="$1"
    if grep -q 'set -e' "$script" 2>/dev/null || grep -q 'set -euo pipefail' "$script" 2>/dev/null; then
        log_pass "Uses strict mode (set -e)"
        return 0
    else
        log_fail "Missing strict mode (set -e or set -euo pipefail)"
        return 1
    fi
}

test_has_stdout_stderr_separation() {
    local script="$1"
    # Check for stderr redirection patterns
    if grep -qE '>&2|1>&2|log_error.*>&2' "$script" 2>/dev/null; then
        log_pass "Has stdout/stderr separation"
        return 0
    else
        log_fail "Missing stdout/stderr separation (errors should go to stderr)"
        return 1
    fi
}

# Run all tests on a single script
test_script() {
    local script="$1"
    local script_name
    script_name=$(basename "$script")
    local script_dir
    script_dir=$(dirname "$script")
    
    log_header "Testing: $script_name"
    log_info "Path: $script"
    
    local failed=0
    
    # Static analysis tests (don't execute script)
    test_is_executable "$script" || ((failed++))
    test_has_shebang "$script" || ((failed++))
    test_has_strict_mode "$script" || ((failed++))
    test_has_help "$script" || ((failed++))
    test_has_version "$script" || ((failed++))
    test_has_stdout_stderr_separation "$script" || ((failed++))
    
    # Dynamic tests (execute script with safe flags)
    test_help_exits_zero "$script" || ((failed++))
    test_version_exits_zero "$script" || ((failed++))
    test_invalid_flag_exits_nonzero "$script" || ((failed++))
    
    if [[ $failed -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed for $script_name${NC}"
        return 0
    else
        echo -e "\n${RED}$failed tests failed for $script_name${NC}"
        return 1
    fi
}

# Find and test scripts
find_addon_scripts() {
    find "${SCRIPT_DIR}/../eks/addons" -name "*.sh" -type f 2>/dev/null || true
}

find_scenario_scripts() {
    find "${SCRIPT_DIR}/../eks/scenarios" -name "*.sh" -type f 2>/dev/null || true
}

find_util_scripts() {
    find "${SCRIPT_DIR}/../eks/utils" -name "*.sh" -type f 2>/dev/null || true
}

# Main
main() {
    log_header "CLI 12-Factor Compliance Tests"
    
    case "$TEST_MODE" in
        all)
            mapfile -t SCRIPTS_TO_TEST < <(find_addon_scripts; find_scenario_scripts; find_util_scripts)
            ;;
        addons)
            mapfile -t SCRIPTS_TO_TEST < <(find_addon_scripts)
            ;;
        scenarios)
            mapfile -t SCRIPTS_TO_TEST < <(find_scenario_scripts)
            ;;
    esac
    
    if [[ ${#SCRIPTS_TO_TEST[@]} -eq 0 ]]; then
        echo "No scripts to test. Provide script path or use --all, --addons, --scenarios" >&2
        exit 1
    fi
    
    local scripts_failed=0
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" ]]; then
            test_script "$script" || ((scripts_failed++))
        fi
    done
    
    # Summary
    log_header "Test Summary"
    echo -e "Total Tests:  $TESTS_RUN"
    echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
    echo -e "Scripts:      ${#SCRIPTS_TO_TEST[@]}"
    echo -e "Scripts OK:   $((${#SCRIPTS_TO_TEST[@]} - scripts_failed))"
    
    if $JSON_OUTPUT; then
        cat << EOF
{
  "tests_run": $TESTS_RUN,
  "tests_passed": $TESTS_PASSED,
  "tests_failed": $TESTS_FAILED,
  "scripts_tested": ${#SCRIPTS_TO_TEST[@]},
  "scripts_failed": $scripts_failed
}
EOF
    fi
    
    if [[ $scripts_failed -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
