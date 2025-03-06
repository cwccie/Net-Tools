#!/bin/bash
# master-setup.sh
# Main orchestration script for NetTools Platform installation

# Exit on any error
set -e

# Script variables
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SCRIPT_PATH}"
LOG_DIR="${INSTALL_DIR}/logs"
CONFIG_DIR="${INSTALL_DIR}/config"
SCRIPT_DIR="${INSTALL_DIR}/scripts"
LOG_FILE="${LOG_DIR}/install.log"
CONFIG_FILE="${CONFIG_DIR}/setup.conf"

# Ensure critical directories exist
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${SCRIPT_DIR}"

# Initialize or clear log file
> "${LOG_FILE}"

# Banner function
print_banner() {
  echo -e "\033[1;34m"
  echo "=================================================="
  echo "    _   _      _   _____           _     "
  echo "   | \ | | ___| |_|_   _|__   ___ | |___ "
  echo "   |  \| |/ _ \ __|| |/ _ \ / _ \| / __|"
  echo "   | |\  |  __/ |_ | | (_) | (_) | \__ \\"
  echo "   |_| \_|\___|\__||_|\___/ \___/|_|___/"
  echo "                                         "
  echo "    Platform Setup - Master Installation Script"
  echo "=================================================="
  echo -e "\033[0m"
  
  echo "$(date '+%Y-%m-%d %H:%M:%S') Starting NetTools Platform Installation" | tee -a "${LOG_FILE}"
}

# Source common functions
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
  source "${SCRIPT_DIR}/lib/common.sh"
else
  echo "Error: Common library not found at ${SCRIPT_DIR}/lib/common.sh"
  echo "Please ensure the common.sh file is properly installed"
  exit 1
fi

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo"
  exit 1
fi

# Component flags with defaults
INSTALL_ENVIRONMENT=true
INSTALL_CORE_INFRA=true
INSTALL_AUTH=false
INSTALL_API_GATEWAY=false
INSTALL_CLUSTER=false
INSTALL_DEVICE=false
INSTALL_MONITORING=false
INSTALL_ADDITIONAL=false
FORCE_INSTALL=false
CONFIG_ONLY=false

# Create or load configuration file
create_default_config() {
  if [ ! -f "${CONFIG_FILE}" ]; then
    log_info "Creating default configuration file at ${CONFIG_FILE}"
    
    cat > "${CONFIG_FILE}" << 'EOL'
# NetTools Platform Installation Configuration

# Installation Directories
INSTALL_DIR="/opt/nettools"
LOG_DIR="${INSTALL_DIR}/logs"
CONFIG_DIR="${INSTALL_DIR}/config"
SCRIPT_DIR="${INSTALL_DIR}/scripts"
MODULES_DIR="${INSTALL_DIR}/modules"
DOCKER_DIR="${INSTALL_DIR}/docker"

# Database Configuration
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="nettools"
DB_USER="nettools"
DB_PASSWORD="nettools"
DB_ADMIN_USER="postgres"
DB_ADMIN_PASSWORD="postgres"

# Docker Configuration
DOCKER_NETWORK="nettools-network"
DOCKER_SUBNET="172.28.0.0/16"

# Node.js Configuration
NODE_VERSION="20.x"
NPM_REGISTRY="https://registry.npmjs.org/"

# Service Ports
API_GATEWAY_PORT="9000"
AUTH_SERVICE_PORT="9001"
DEVICE_SERVICE_PORT="9002"
MONITORING_SERVICE_PORT="9003"
CLUSTER_SERVICE_PORT="9004"

# Docker Service Ports
TIMESCALEDB_PORT="5432"
REDIS_PORT="6379"
VAULT_PORT="8200"
PROMETHEUS_PORT="9090"
GRAFANA_PORT="3001"

# System User
NETTOOLS_USER="nettools"
NETTOOLS_GROUP="nettools"

# Deployment Environment
ENVIRONMENT="development" # Options: development, staging, production

# Security Configuration
JWT_SECRET="change-this-in-production"
REFRESH_TOKEN_SECRET="change-this-in-production"
EOL
  else
    log_info "Configuration file ${CONFIG_FILE} already exists"
  fi
}

# Load the configuration
load_configuration() {
  if [ -f "${CONFIG_FILE}" ]; then
    log_info "Loading configuration from ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
  else
    log_error "Configuration file ${CONFIG_FILE} not found"
    exit 1
  fi
}

# Parse command line arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env-only)
        INSTALL_CORE_INFRA=false
        INSTALL_AUTH=false
        INSTALL_API_GATEWAY=false
        INSTALL_CLUSTER=false
        INSTALL_DEVICE=false
        INSTALL_MONITORING=false
        INSTALL_ADDITIONAL=false
        shift
        ;;
      --core-only)
        INSTALL_ENVIRONMENT=false
        INSTALL_AUTH=false
        INSTALL_API_GATEWAY=false
        INSTALL_CLUSTER=false
        INSTALL_DEVICE=false
        INSTALL_MONITORING=false
        INSTALL_ADDITIONAL=false
        shift
        ;;
      --with-auth)
        INSTALL_AUTH=true
        shift
        ;;
      --with-api)
        INSTALL_API_GATEWAY=true
        shift
        ;;
      --with-cluster)
        INSTALL_CLUSTER=true
        shift
        ;;
      --with-device)
        INSTALL_DEVICE=true
        shift
        ;;
      --with-monitoring)
        INSTALL_MONITORING=true
        shift
        ;;
      --with-additional)
        INSTALL_ADDITIONAL=true
        shift
        ;;
      --all)
        INSTALL_ENVIRONMENT=true
        INSTALL_CORE_INFRA=true
        INSTALL_AUTH=true
        INSTALL_API_GATEWAY=true
        INSTALL_CLUSTER=true
        INSTALL_DEVICE=true
        INSTALL_MONITORING=true
        INSTALL_ADDITIONAL=true
        shift
        ;;
      --force)
        FORCE_INSTALL=true
        shift
        ;;
      --config-only)
        CONFIG_ONLY=true
        INSTALL_ENVIRONMENT=false
        INSTALL_CORE_INFRA=false
        INSTALL_AUTH=false
        INSTALL_API_GATEWAY=false
        INSTALL_CLUSTER=false
        INSTALL_DEVICE=false
        INSTALL_MONITORING=false
        INSTALL_ADDITIONAL=false
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

# Show help information
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --env-only         Install only the environment setup"
  echo "  --core-only        Install only the core infrastructure"
  echo "  --with-auth        Include authentication module"
  echo "  --with-api         Include API gateway module"
  echo "  --with-cluster     Include cluster module"
  echo "  --with-device      Include device discovery module"
  echo "  --with-monitoring  Include monitoring module"
  echo "  --with-additional  Include additional modules"
  echo "  --all              Install all components"
  echo "  --force            Force installation even if components already exist"
  echo "  --config-only      Only create or update configuration files, don't install anything"
  echo "  --help, -h         Show this help message"
  echo ""
  echo "By default, only environment and core infrastructure are installed."
}

# Check dependencies for a component
check_component_dependencies() {
  local component="$1"
  
  case $component in
    environment)
      # Environment has no dependencies
      return 0
      ;;
    core-infra)
      # Core infrastructure depends on environment
      if [ "$INSTALL_ENVIRONMENT" != "true" ] && [ ! -f "${SCRIPT_DIR}/.env_installed" ]; then
        log_error "Core infrastructure depends on environment, which is not installed"
        return 1
      fi
      return 0
      ;;
    auth)
      # Auth depends on core infrastructure
      if [ "$INSTALL_CORE_INFRA" != "true" ] && [ ! -f "${SCRIPT_DIR}/.core_infra_installed" ]; then
        log_error "Authentication module depends on core infrastructure, which is not installed"
        return 1
      fi
      return 0
      ;;
    api-gateway)
      # API gateway depends on auth
      if [ "$INSTALL_AUTH" != "true" ] && [ ! -f "${SCRIPT_DIR}/.auth_installed" ]; then
        log_error "API gateway depends on authentication module, which is not installed"
        return 1
      fi
      return 0
      ;;
    *)
      # Other components depend on core infrastructure
      if [ "$INSTALL_CORE_INFRA" != "true" ] && [ ! -f "${SCRIPT_DIR}/.core_infra_installed" ]; then
        log_error "Component ${component} depends on core infrastructure, which is not installed"
        return 1
      fi
      return 0
      ;;
  esac
}

# Execute a component script
execute_component() {
  local component="$1"
  local script="${SCRIPT_DIR}/${component}.sh"
  
  if [ ! -f "$script" ]; then
    log_error "Component script not found: $script"
    return 1
  fi
  
  log_section "Installing component: $component"
  
  # Check if component is already installed and FORCE_INSTALL is not set
  if [ -f "${SCRIPT_DIR}/.${component}_installed" ] && [ "$FORCE_INSTALL" != "true" ]; then
    log_warning "Component $component is already installed. Use --force to reinstall."
    return 0
  fi
  
  # Check dependencies
  check_component_dependencies "$component" || return 1
  
  # Execute the script
  chmod +x "$script"
  if ! "$script"; then
    log_error "Failed to install component: $component"
    return 1
  fi
  
  # Mark component as installed
  touch "${SCRIPT_DIR}/.${component}_installed"
  log_success "Component $component installed successfully"
  
  return 0
}

# Verify installation
verify_installation() {
  log_section "Verifying NetTools Platform Installation"
  
  local errors=0
  
  # Verify that installed components are working properly
  if [ -f "${SCRIPT_DIR}/.environment_installed" ]; then
    log_info "Verifying environment setup..."
    # Add specific checks for environment
    if command_exists docker && command_exists node; then
      log_success "Environment setup verified"
    else
      log_error "Environment verification failed"
      errors=$((errors + 1))
    fi
  fi
  
  if [ -f "${SCRIPT_DIR}/.core_infra_installed" ]; then
    log_info "Verifying core infrastructure..."
    # Check Docker containers
    if docker ps | grep -q "nettools-timescaledb" && \
       docker ps | grep -q "nettools-redis"; then
      log_success "Core infrastructure verified"
    else
      log_error "Core infrastructure verification failed"
      errors=$((errors + 1))
    fi
  fi
  
  if [ $errors -eq 0 ]; then
    log_success "All installed components verified successfully"
  else
    log_error "$errors component(s) failed verification"
  fi
}

# Main installation function
install_nettools() {
  # Install components based on flags
  if [ "$INSTALL_ENVIRONMENT" = "true" ]; then
    execute_component "1-environment-setup" || return 1
  fi
  
  if [ "$INSTALL_CORE_INFRA" = "true" ]; then
    execute_component "2-core-infrastructure" || return 1
  fi
  
  if [ "$INSTALL_AUTH" = "true" ]; then
    execute_component "3-auth-module" || return 1
  fi
  
  if [ "$INSTALL_API_GATEWAY" = "true" ]; then
    execute_component "4-api-gateway-module" || return 1
  fi
  
  if [ "$INSTALL_CLUSTER" = "true" ]; then
    execute_component "5-cluster-module" || return 1
  fi
  
  if [ "$INSTALL_DEVICE" = "true" ]; then
    execute_component "6-device-discovery-module" || return 1
  fi
  
  if [ "$INSTALL_MONITORING" = "true" ]; then
    execute_component "7-monitoring-module" || return 1
  fi
  
  if [ "$INSTALL_ADDITIONAL" = "true" ]; then
    execute_component "8-additional-modules" || return 1
  fi
  
  return 0
}

# Cleanup function
cleanup() {
  log_section "Cleaning up"
  # Add any cleanup tasks here
  log_info "Cleanup completed"
}

# Main function
main() {
  print_banner
  
  # Parse command line arguments
  parse_arguments "$@"
  
  # Create or load configuration
  create_default_config
  load_configuration
  
  if [ "$CONFIG_ONLY" = "true" ]; then
    log_success "Configuration files created/updated successfully"
    exit 0
  fi
  
  # Check system requirements before proceeding
  check_system_resources
  print_system_summary
  
  # Confirm installation
  if ! confirm "Ready to install NetTools Platform. Continue?"; then
    log_info "Installation aborted by user"
    exit 0
  fi
  
  # Start installation
  if install_nettools; then
    verify_installation
    log_success "NetTools Platform installation completed successfully"
  else
    log_error "NetTools Platform installation failed"
    cleanup
    exit 1
  fi
}

# Run main function with all arguments
main "$@"
