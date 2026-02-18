#!/usr/bin/env bash

# --- Configuration & Styling ---
set -e

# Colors for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Symbols
CHECKMARK="✅"
ERROR_X="❌"
INFO_BULLET="ℹ️"
STAR="🌟"
ARROW="➜"

# --- Constants ---
INSTALL_FILE=".installed"
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"
AUTH_DIR=".suite-auth"
AUTH_FILE="$AUTH_DIR/.github-auth"

# --- Logging Helpers ---
print_banner() {
    echo -e "${PURPLE}${BOLD}"
    echo "=============================================="
    echo "    Snapsec On-Premises Setup Utility        "
    echo "=============================================="
    echo -e "${NC}"
}

log_info() { echo -e "${BLUE}${BOLD}${INFO_BULLET} [INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}${BOLD}${CHECKMARK} [SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}${BOLD}⚠️ [WARN]${NC} $1"; }
log_error() { echo -e "${RED}${BOLD}${ERROR_X} [ERROR]${NC} $1"; }
log_step() { echo -e "\n${CYAN}${BOLD}${ARROW} $1${NC}"; }

# --- Interactive Helpers ---
confirm() {
    local prompt="$1"
    local default="$2" # "y" or "n"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$(echo -e "${BOLD}${prompt} [Y/n]: ${NC}")" response
        else
            read -p "$(echo -e "${BOLD}${prompt} [y/N]: ${NC}")" response
        fi
        
        case "${response,,}" in
            y|yes|"") return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

# --- Module: System Checks ---
# --- Module: Dependency Management ---

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

install_dependency() {
    local dep=$1
    local pkg_manager=$(detect_package_manager)
    
    log_info "Attempting to install $dep using $pkg_manager..."
    
    case "$pkg_manager" in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y "$dep"
            ;;
        yum)
            sudo yum install -y "$dep"
            ;;
        pacman)
            # On Arch, cron is usually 'cronie'
            if [[ "$dep" == "cron" ]]; then dep="cronie"; fi
            sudo pacman -Sy --nocolor --noconfirm "$dep"
            ;;
        *)
            log_error "Unsupported package manager. Please install $dep manually."
            return 1
            ;;
    esac
}

check_dependencies() {
    log_step "Verifying system requirements..."
    
    local deps=("docker" "docker-compose" "openssl" "crontab")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            if [[ "$dep" == "crontab" ]]; then
                missing_deps+=("cron")
            else
                missing_deps+=("$dep")
            fi
        else
            log_info "$dep found."
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warn "The following dependencies are missing: ${missing_deps[*]}"
        if confirm "Would you like to attempt to install missing dependencies automatically?" "y"; then
            for m_dep in "${missing_deps[@]}"; do
                install_dependency "$m_dep"
            done
            # Re-verify
            check_dependencies
        else
            log_error "Cannot proceed without dependencies. Please install them and try again."
            exit 1
        fi
    else
        log_success "All critical dependencies are present."
    fi
}

# --- Module: Environment Setup ---
generate_random_key() {
    openssl rand -hex 32
}

setup_env() {
    log_step "Configuring environment variables..."

    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$ENV_EXAMPLE" ]]; then
            log_info "Creating $ENV_FILE from $ENV_EXAMPLE..."
            cp "$ENV_EXAMPLE" "$ENV_FILE"
        else
            log_error "$ENV_EXAMPLE not found! Cannot initialize $ENV_FILE."
            exit 1
        fi
    fi

    local host_url=""
    while [[ -z "$host_url" ]]; do
        read -p "$(echo -e "${BOLD}Enter the URL on which the app will be hosted (e.g., https://suite.snapsec.co): ${NC}")" host_url
        if [[ ! "$host_url" =~ ^https?:// ]]; then
            log_warn "URL must start with http:// or https://"
            host_url=""
        fi
    done

    log_info "Updating BASE_URL, ENCRYPTION_KEY, and SERVICE_KEY..."
    
    local enc_key=$(generate_random_key)
    local srv_key=$(generate_random_key)

    # BASE_URL
    if grep -q "^BASE_URL=" "$ENV_FILE"; then
        sed -i "s|^BASE_URL=.*|BASE_URL=$host_url|" "$ENV_FILE"
    else
        echo "BASE_URL=$host_url" >> "$ENV_FILE"
    fi

    # ENCRYPTION_KEY
    if grep -q "^ENCRYPTION_KEY=" "$ENV_FILE"; then
        sed -i "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$enc_key|" "$ENV_FILE"
    else
        echo "ENCRYPTION_KEY=$enc_key" >> "$ENV_FILE"
    fi

    # SERVICE_KEY
    if grep -q "^SERVICE_KEY=" "$ENV_FILE"; then
        sed -i "s|^SERVICE_KEY=.*|SERVICE_KEY=$srv_key|" "$ENV_FILE"
    else
        echo "SERVICE_KEY=$srv_key" >> "$ENV_FILE"
    fi

    log_success "Environment configuration updated in $ENV_FILE."
}

setup_keys() {
    log_step "Generating security keys..."
    local keys_dir="keys"
    
    if [[ ! -d "$keys_dir" ]]; then
        log_info "Creating $keys_dir directory..."
        mkdir -p "$keys_dir"
    fi

    if [[ -f "$keys_dir/private.pem" && -f "$keys_dir/public.pem" ]]; then
        log_info "Security keys already exist."
    else
        log_info "Generating RSA private and public keys..."
        openssl genrsa -out "$keys_dir/private.pem" 2048
        openssl rsa -in "$keys_dir/private.pem" -pubout -out "$keys_dir/public.pem"
        log_success "Security keys generated successfully."
    fi
}

# --- Module: Cron Job ---
setup_cron() {
    log_step "Scheduling weekly maintenance..."
    
    if ! command -v crontab &> /dev/null; then
        log_warn "Crontab not available, skipping cron setup."
        return
    fi

    local script_path="$(realpath "$0")"
    local script_dir="$(dirname "$script_path")"
    local cron_job="0 0 * * 0 cd $script_dir && ./setup.sh update >> $script_dir/update.log 2>&1"
    
    # Check if already exists
    if crontab -l 2>/dev/null | grep -q "$script_path update"; then
        log_info "Weekly update cron job is already scheduled."
    else
        log_info "Adding weekly update cron job (every Sunday at midnight)..."
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log_success "Maintenance schedule established."
    fi
}

# --- Module: State Management ---
check_is_installed() {
    if [[ ! -f "$INSTALL_FILE" ]]; then
        log_error "Application is not installed. Please run './setup.sh install' first."
        exit 1
    fi
}

mark_installed() {
    touch "$INSTALL_FILE"
    log_info "Installation state saved."
}

# --- Module: Registry Authentication ---
ensure_registry_auth() {
    log_step "Registry Authentication"
    local github_token=""

    if [[ -f "$AUTH_FILE" ]]; then
        log_info "using cached credentials from $AUTH_FILE..."
        github_token=$(cat "$AUTH_FILE")
    fi

    if [[ -z "$github_token" ]]; then
        while [[ -z "$github_token" ]]; do
            read -sp "$(echo -e "${BOLD}Enter your GitHub Pull-Only Token: ${NC}")" github_token
            echo "" # New line after silent input
            if [[ -z "$github_token" ]]; then
                log_warn "Token cannot be empty."
            fi
        done
    fi

    log_info "Logging into ghcr.io..."
    if echo "$github_token" | docker login ghcr.io -u faizanalibhat --password-stdin &>/dev/null; then
        log_success "Successfully authenticated with ghcr.io."
        # Save the token for future use
        mkdir -p "$AUTH_DIR"
        echo "$github_token" > "$AUTH_FILE"
        chmod 600 "$AUTH_FILE" # Protect the token file
    else
        log_error "Failed to authenticate with ghcr.io. Please check your token."
        # If it failed with a cached token, clear it so we re-prompt next time
        if [[ -f "$AUTH_FILE" ]]; then
            rm "$AUTH_FILE"
            log_info "Cached token was invalid and has been removed."
        fi
        exit 1
    fi
}

# --- Command Handlers ---

handle_install() {
    print_banner
    
    if [[ -f "$INSTALL_FILE" ]]; then
        log_warn "Application is already installed."
        if confirm "Re-installing will remove all images and start fresh. Continue?" "n"; then
            log_info "Removing existing infrastructure and images..."
            docker-compose down --rmi all
        else
            log_info "Aborting installation."
            exit 0
        fi
    fi

    log_info "Starting fresh installation..."
    
    check_dependencies
    setup_env
    setup_keys
    
    log_step "Telemetry Opt-in"
    local telemetry_pref=""
    if [[ -n "$TELEMETRY_CHOICE" ]]; then
        telemetry_pref="$TELEMETRY_CHOICE"
    else
        if confirm "Would you like to enable anonymous telemetry to help improve the platform and resolve bugs ?" "y"; then
            telemetry_pref="true"
        else
            telemetry_pref="false"
        fi
    fi

    if [[ "$telemetry_pref" == "true" ]]; then
        sed -i "s|^ENABLE_TELEMETRY=.*|ENABLE_TELEMETRY=true|" "$ENV_FILE" 2>/dev/null || echo "ENABLE_TELEMETRY=true" >> "$ENV_FILE"
        log_success "Telemetry enabled."
    else
        sed -i "s|^ENABLE_TELEMETRY=.*|ENABLE_TELEMETRY=false|" "$ENV_FILE" 2>/dev/null || echo "ENABLE_TELEMETRY=false" >> "$ENV_FILE"
        log_info "Telemetry disabled."
    fi

    ensure_registry_auth

    log_step "Provisioning Containers"
    log_info "Pulling latest docker images..."
    if ! docker-compose pull; then
        log_error "Failed to pull docker images."
        log_info "Please ensure your token has the 'read:packages' scope."
        exit 1
    fi
    
    log_info "Ensuring infrastructure is stopped before starting..."
    docker-compose down 2>/dev/null || true

    log_info "Starting services in detached mode..."
    if ! docker-compose up -d; then
        log_error "Failed to start services."
        exit 1
    fi
    
    setup_cron
    mark_installed
    
    log_success "Installation completed successfully! ${STAR}"
    echo -e "\nYou can now access the application. Detailed logs are available via 'docker-compose logs -f'."
}

handle_update() {
    print_banner
    check_is_installed
    
    log_info "Starting update process..."
    
    ensure_registry_auth

    log_step "Fetching Updates"
    log_info "Updating container images..."
    if ! docker-compose pull; then
        log_error "Failed to pull updated images."
        exit 1
    fi
    
    log_info "Ensuring infrastructure is stopped before restarting..."
    docker-compose down 2>/dev/null || true

    log_step "Restarting Services"
    docker-compose up -d --remove-orphans
    
    log_step "Cleaning up old images"
    docker image prune -f
    
    log_success "Application updated successfully! ${STAR}"
}

handle_start() {
    print_banner
    check_is_installed
    log_info "Starting infrastructure..."
    
    log_info "Ensuring infrastructure is stopped before starting..."
    docker-compose down 2>/dev/null || true
    
    log_step "Starting services"
    if ! docker-compose up -d; then
        log_error "Failed to start services."
        exit 1
    fi
    log_success "Infrastructure started successfully! ${STAR}"
}

handle_stop() {
    print_banner
    check_is_installed
    log_info "Stopping infrastructure..."
    docker-compose down
    log_success "Infrastructure stopped successfully! ${NC}"
}

# --- Main CLI Router ---

show_help() {
    print_banner
    echo -e "Usage: $0 ${BOLD}[COMMAND] [OPTIONS]${NC}"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  install          Run the interactive installation process"
    echo "  update           Update the application and restart services"
    echo "  start            Start the infrastructure services"
    echo "  stop             Stop the infrastructure services"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --no-telemetry   Disable telemetry (non-interactive install)"
    echo "  --telemetry      Enable telemetry (non-interactive install)"
    echo "  -h, --help       Show this help message"
    echo ""
}

COMMAND=""
TELEMETRY_CHOICE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        install|update|start|stop)
            COMMAND="$1"
            shift
            ;;
        --no-telemetry)
            TELEMETRY_CHOICE="false"
            shift
            ;;
        --telemetry)
            TELEMETRY_CHOICE="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    log_error "No command specified."
    show_help
    exit 1
fi

case "$COMMAND" in
    install)
        handle_install
        ;;
    update)
        handle_update
        ;;
    start)
        handle_start
        ;;
    stop)
        handle_stop
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        exit 1
        ;;
esac
