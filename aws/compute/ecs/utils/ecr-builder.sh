#!/usr/bin/env bash
# Build and push Docker image to ECR
# CLI 12-Factor Compliant

set -euo pipefail

SCRIPT_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build a Docker image and push to Amazon ECR.

OPTIONS:
    --name NAME           Image/repository name (required)
    --region REGION       AWS region (default: us-east-1)
    --tag TAG             Image tag (default: latest)
    --dockerfile PATH     Dockerfile path (default: ./Dockerfile)
    --context PATH        Build context path (default: .)
    --build-only          Build only, don't push
    --push-only           Push only, assume image exists
    --create-repo         Create ECR repo if not exists
    --dry-run             Show what would happen
    -h, --help            Show this help message
    -v, --version         Show script version

EXAMPLES:
    # Build and push with defaults
    $(basename "$0") --name my-app

    # Build and push with specific tag
    $(basename "$0") --name my-app --tag v1.2.3

    # Build only (no push)
    $(basename "$0") --name my-app --build-only

    # Different region
    $(basename "$0") --name my-app --region us-west-2

    # Dry run
    $(basename "$0") --name my-app --dry-run
EOF
}

show_version() {
    echo "$(basename "$0") version ${SCRIPT_VERSION}"
}

# Logging - separate stdout/stderr
log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&1; }
log_success() { echo -e "${GREEN}[OK]${NC} $*" >&1; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "\n${YELLOW}=== $* ===${NC}" >&1; }

# Defaults
IMAGE_NAME=""
REGION="us-east-1"
TAG="latest"
DOCKERFILE="./Dockerfile"
BUILD_CONTEXT="."
BUILD_ONLY=false
PUSH_ONLY=false
CREATE_REPO=true
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --dockerfile)
            DOCKERFILE="$2"
            shift 2
            ;;
        --context)
            BUILD_CONTEXT="$2"
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --push-only)
            PUSH_ONLY=true
            shift
            ;;
        --create-repo)
            CREATE_REPO=true
            shift
            ;;
        --no-create-repo)
            CREATE_REPO=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
        *)
            log_error "Unknown option: $1"
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# Validate required args
if [[ -z "$IMAGE_NAME" ]]; then
    log_error "Image name required. Use --name"
    exit 1
fi

# Get AWS account
get_account() {
    aws sts get-caller-identity --query Account --output text
}

main() {
    log_step "Configuration"
    
    local account
    account=$(get_account)
    
    local repository="${account}.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}:${TAG}"
    
    log_info "Image Name: $IMAGE_NAME"
    log_info "Tag: $TAG"
    log_info "Region: $REGION"
    log_info "Account: $account"
    log_info "Repository: $repository"
    
    if $DRY_RUN; then
        log_step "Dry Run Summary"
        [[ "$CREATE_REPO" == true ]] && log_info "Would create ECR repo if not exists"
        [[ "$PUSH_ONLY" != true ]] && log_info "Would build: docker build -t $IMAGE_NAME -f $DOCKERFILE $BUILD_CONTEXT"
        [[ "$BUILD_ONLY" != true ]] && log_info "Would push to: $repository"
        exit 0
    fi
    
    # Create repo if needed
    if $CREATE_REPO && ! $BUILD_ONLY; then
        log_step "ECR Repository"
        if aws ecr describe-repositories --repository-names "$IMAGE_NAME" --region "$REGION" > /dev/null 2>&1; then
            log_success "Repository exists"
        else
            log_info "Creating repository..."
            aws ecr create-repository --repository-name "$IMAGE_NAME" --region "$REGION" > /dev/null
            log_success "Repository created"
        fi
    fi
    
    # Build
    if ! $PUSH_ONLY; then
        log_step "Building Image"
        log_info "Dockerfile: $DOCKERFILE"
        log_info "Context: $BUILD_CONTEXT"
        
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$BUILD_CONTEXT"
        log_success "Image built"
        
        docker tag "$IMAGE_NAME" "$repository"
        log_success "Image tagged: $repository"
    fi
    
    # Push
    if ! $BUILD_ONLY; then
        log_step "Authenticating to ECR"
        aws ecr get-login-password --region "$REGION" | \
            docker login --username AWS --password-stdin "${account}.dkr.ecr.${REGION}.amazonaws.com"
        log_success "Authenticated"
        
        log_step "Pushing Image"
        docker push "$repository"
        log_success "Image pushed: $repository"
    fi
    
    log_step "Complete"
    log_info "Repository: $repository"
    exit 0
}

main "$@"
