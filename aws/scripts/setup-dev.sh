#!/usr/bin/env bash
#
# setup-dev.sh - Set up aws-lab development environment
#
# Usage:
#   ./scripts/setup-dev.sh
#   ./scripts/setup-dev.sh --help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_ROOT
readonly VERSION="1.0.0"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${BLUE}=== $* ===${NC}\n"; }

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Set up aws-lab development environment.

Options:
  --help          Show this help message
  --version       Show version
  --skip-optional Skip optional tool installation
  --check-only    Only check tools, don't configure

Required Tools:
  - terraform (>= 1.5.0)
  - aws-cli
  - tflint
  - tfsec

Optional Tools:
  - pre-commit
  - terraform-docs
  - infracost
  - checkov
  - go (for Terratest)

EOF
}

check_command() {
  command -v "$1" &> /dev/null
}

get_version() {
  local cmd="$1"
  case "$cmd" in
    terraform) terraform version -json 2> /dev/null | jq -r '.terraform_version' 2> /dev/null || terraform version | head -1 | awk '{print $2}' ;;
    aws) aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2 ;;
    tflint) tflint --version | head -1 | awk '{print $3}' ;;
    tfsec) tfsec --version 2> /dev/null | head -1 ;;
    terraform-docs) terraform-docs --version | awk '{print $3}' ;;
    infracost) infracost --version | awk '{print $2}' ;;
    checkov) checkov --version 2> /dev/null ;;
    pre-commit) pre-commit --version | awk '{print $2}' ;;
    go) go version | awk '{print $3}' | cut -c3- ;;
    *) echo "unknown" ;;
  esac
}

check_tool() {
  local tool="$1"
  local required="${2:-true}"

  if check_command "$tool"; then
    local version
    version=$(get_version "$tool")
    log_success "$tool ($version)"
    return 0
  else
    if [[ "$required" == "true" ]]; then
      log_error "$tool - NOT INSTALLED (required)"
      return 1
    else
      log_warn "$tool - not installed (optional)"
      return 0
    fi
  fi
}

main() {
  local skip_optional=false
  local check_only=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --help)
        show_help
        exit 0
        ;;
      --version)
        echo "$VERSION"
        exit 0
        ;;
      --skip-optional)
        skip_optional=true
        shift
        ;;
      --check-only)
        check_only=true
        shift
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  log_section "aws-lab Development Environment Setup"

  local has_errors=false

  log_section "Required Tools"
  check_tool "terraform" "true" || has_errors=true
  check_tool "aws" "true" || has_errors=true
  check_tool "tflint" "true" || has_errors=true
  check_tool "tfsec" "true" || has_errors=true

  if [[ "$skip_optional" != "true" ]]; then
    log_section "Optional Tools"
    check_tool "terraform-docs" "false" || true
    check_tool "pre-commit" "false" || true
    check_tool "infracost" "false" || true
    check_tool "checkov" "false" || true
    check_tool "go" "false" || true
  fi

  if [[ "$check_only" == "true" ]]; then
    if [[ "$has_errors" == "true" ]]; then
      log_error "Some required tools are missing!"
      exit 1
    fi
    log_success "All required tools installed!"
    exit 0
  fi

  if [[ "$has_errors" == "true" ]]; then
    log_error "Cannot continue: required tools missing."
    exit 1
  fi

  log_section "Configuring Environment"

  # Check AWS credentials
  log_info "Checking AWS credentials..."
  if aws sts get-caller-identity &> /dev/null; then
    local account_id
    account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    log_success "AWS configured (Account: $account_id)"
  else
    log_warn "AWS credentials not configured. Run 'aws configure'"
  fi

  # Install pre-commit hooks
  if check_command "pre-commit"; then
    log_info "Installing pre-commit hooks..."
    cd "$PROJECT_ROOT"
    pre-commit install || log_warn "Failed to install pre-commit hooks"
    pre-commit install --hook-type commit-msg || true
    log_success "Pre-commit hooks installed"
  fi

  # Initialize TFLint plugins
  log_info "Initializing TFLint plugins..."
  cd "$PROJECT_ROOT"
  tflint --init || log_warn "TFLint init failed (plugins may not install)"

  log_section "Setup Complete"

  echo "Your development environment is ready!"
  echo ""
  echo "Quick start:"
  echo "  1. Check AWS identity:     aws sts get-caller-identity"
  echo "  2. Validate Terraform:     terraform validate"
  echo "  3. Run linters:            make lint"
  echo ""
  echo "For more information, see README.md"
}

main "$@"
