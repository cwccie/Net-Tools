#!/bin/bash
# 1-environment-setup.sh
# Setup the server environment for NetTools Platform

# Exit on any error
set -e

# Set script directory as current directory's parent if not provided
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "${SCRIPT_PATH}")"
SCRIPT_DIR="${INSTALL_DIR}/scripts"
LOG_DIR="${INSTALL_DIR}/logs"
CONFIG_DIR="${INSTALL_DIR}/config"
LOG_FILE="${LOG_DIR}/install.log"
CONFIG_FILE="${CONFIG_DIR}/setup.conf"

# Source common functions
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
  source "${SCRIPT_DIR}/lib/common.sh"
else
  echo "Error: Common library not found at ${SCRIPT_DIR}/lib/common.sh"
  echo "Please ensure the common.sh file is properly installed"
  exit 1
fi

# Load configuration
if [ -f "${CONFIG_FILE}" ]; then
  source "${CONFIG_FILE}"
else
  log_error "Configuration file not found at ${CONFIG_FILE}"
  exit 1
fi

# Check system requirements
check_system_requirements() {
  log_section "Checking system requirements"

  # Check OS
  if ! command_exists lsb_release; then
    apt-get update && apt-get install -y lsb-release
  fi
  
  local os_id=$(lsb_release -is)
  local os_version=$(lsb_release -rs)
  
  if [[ "$os_id" != "Ubuntu" ]]; then
    log_warning "This script is designed for Ubuntu, but detected ${os_id}. Some features may not work correctly."
  else
    log_info "Detected OS: ${os_id} ${os_version}"
  fi

  # Check if systemd is available
  if ! command_exists systemctl; then
    log_error "systemd is required but not found"
    return 1
  fi

  # Check disk space
  check_system_resources 4096 10240 2
  
  return 0
}

# Update package repositories
update_packages() {
  log_section "Updating package repositories"
  
  log_info "Updating apt package lists"
  apt-get update || { log_error "Failed to update apt package lists"; return 1; }
  
  log_info "Upgrading installed packages"
  apt-get upgrade -y || { log_warning "Some packages could not be upgraded"; }
  
  log_info "Installing prerequisites"
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    jq \
    git \
    acl || { log_error "Failed to install prerequisites"; return 1; }
    
  log_success "Package repositories updated successfully"
  return 0
}

# Install Docker
install_docker() {
  log_section "Installing Docker"
  
  if command_exists docker && command_exists docker-compose; then
    log_info "Docker and Docker Compose are already installed"
    docker --version | tee -a "${LOG_FILE}"
    docker-compose --version | tee -a "${LOG_FILE}"
    return 0
  fi
  
  log_info "Adding Docker's official GPG key"
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  
  log_info "Setting up Docker repository"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  log_info "Installing Docker packages"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  
  log_info "Adding user ${NETTOOLS_USER} to docker group (if user exists)"
  if id "${NETTOOLS_USER}" &>/dev/null; then
    usermod -aG docker "${NETTOOLS_USER}"
  fi
  
  log_info "Verifying Docker installation"
  docker --version | tee -a "${LOG_FILE}"
  docker compose version | tee -a "${LOG_FILE}"
  
  log_success "Docker installed successfully"
  return 0
}

# Install Node.js
install_nodejs() {
  log_section "Installing Node.js"
  
  if command_exists node && command_exists npm; then
    local node_version=$(node -v)
    log_info "Node.js is already installed: ${node_version}"
    
    # Check if version meets requirements
    if [[ "${node_version}" =~ ^v([0-9]+)\. ]]; then
      local major_version="${BASH_REMATCH[1]}"
      if [[ "${major_version}" -ge 20 ]]; then
        log_success "Node.js version is sufficient"
        return 0
      else
        log_warning "Node.js version ${node_version} is below recommended version 20.x"
        # Continue with installation to upgrade
      fi
    fi
  fi
  
  log_info "Setting up Node.js repository"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}" | bash -
  
  log_info "Installing Node.js"
  apt-get install -y nodejs
  
  log_info "Verifying Node.js installation"
  node --version | tee -a "${LOG_FILE}"
  npm --version | tee -a "${LOG_FILE}"
  
  log_success "Node.js installed successfully"
  return 0
}

# Set up NetTools user and group
setup_user() {
  log_section "Setting up NetTools user and group"
  
  if ! getent group "${NETTOOLS_GROUP}" >/dev/null; then
    log_info "Creating group ${NETTOOLS_GROUP}"
    groupadd "${NETTOOLS_GROUP}"
  else
    log_info "Group ${NETTOOLS_GROUP} already exists"
  fi
  
  if ! id "${NETTOOLS_USER}" &>/dev/null; then
    log_info "Creating user ${NETTOOLS_USER}"
    useradd -m -g "${NETTOOLS_GROUP}" -s /bin/bash "${NETTOOLS_USER}"
    
    log_info "Setting up user home directory"
    mkdir -p "/home/${NETTOOLS_USER}/.ssh"
    cp /etc/skel/.* "/home/${NETTOOLS_USER}/" 2>/dev/null || true
    chown -R "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "/home/${NETTOOLS_USER}"
  else
    log_info "User ${NETTOOLS_USER} already exists"
  fi
  
  log_success "NetTools user and group setup completed"
  return 0
}

# Create NetTools directory structure
create_directory_structure() {
  log_section "Creating NetTools directory structure"
  
  # Create main directories with appropriate permissions
  log_info "Creating main directories"
  create_directory "${INSTALL_DIR}" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${LOG_DIR}" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${CONFIG_DIR}" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${SCRIPT_DIR}" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${MODULES_DIR}" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${DOCKER_DIR}" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${DOCKER_DIR}/development" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${DOCKER_DIR}/development/volumes" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${DOCKER_DIR}/development/config" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  
  # Create module directories
  log_info "Creating module directories"
  for module in auth api-gateway cluster device monitoring; do
    create_directory "${MODULES_DIR}/${module}" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
    create_directory "${MODULES_DIR}/${module}/Backend" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
    create_directory "${MODULES_DIR}/${module}/Frontend" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
    create_directory "${MODULES_DIR}/${module}/Specification" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  done
  
  # Set appropriate permissions
  log_info "Setting directory permissions"
  find "${INSTALL_DIR}" -type d -exec chmod 0755 {} \;
  find "${INSTALL_DIR}" -type f -exec chmod 0644 {} \;
  chmod 0755 "${INSTALL_DIR}/master-setup.sh"
  find "${SCRIPT_DIR}" -name "*.sh" -exec chmod 0755 {} \;
  
  log_success "Directory structure created successfully"
  return 0
}

# Setup environment variables
setup_environment_variables() {
  log_section "Setting up environment variables"
  
  log_info "Creating .env file"
  cat > "${INSTALL_DIR}/.env" << EOL
# NetTools Environment Variables
NETTOOLS_HOME=${INSTALL_DIR}
NETTOOLS_CONFIG=${CONFIG_DIR}
NETTOOLS_LOGS=${LOG_DIR}
NETTOOLS_USER=${NETTOOLS_USER}
NETTOOLS_GROUP=${NETTOOLS_GROUP}
PATH=\$PATH:${INSTALL_DIR}/scripts
EOL
  
  log_info "Setting permissions on .env file"
  chmod 0644 "${INSTALL_DIR}/.env"
  chown "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "${INSTALL_DIR}/.env"
  
  log_info "Adding environment variables to /etc/profile.d/"
  cat > "/etc/profile.d/nettools.sh" << EOL
#!/bin/bash
# NetTools environment variables
export NETTOOLS_HOME=${INSTALL_DIR}
export NETTOOLS_CONFIG=${CONFIG_DIR}
export NETTOOLS_LOGS=${LOG_DIR}
export PATH=\$PATH:${INSTALL_DIR}/scripts
EOL
  
  chmod 0755 "/etc/profile.d/nettools.sh"
  
  log_success "Environment variables set up successfully"
  return 0
}

# Create helper scripts
create_helper_scripts() {
  log_section "Creating helper scripts"
  
  log_info "Creating service control script"
  cat > "${SCRIPT_DIR}/nettools-control.sh" << 'EOL'
#!/bin/bash
# nettools-control.sh
# Control NetTools services

INSTALL_DIR=${NETTOOLS_HOME:-"/opt/nettools"}
SCRIPT_DIR="${INSTALL_DIR}/scripts"
DOCKER_DIR="${INSTALL_DIR}/docker/development"

# Source common functions
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  echo "Usage: $0 {start|stop|restart|status}"
  echo
  echo "Commands:"
  echo "  start   - Start all NetTools services"
  echo "  stop    - Stop all NetTools services"
  echo "  restart - Restart all NetTools services"
  echo "  status  - Show status of all NetTools services"
  exit 1
}

check_status() {
  log_section "NetTools Service Status"
  
  # Check Docker containers
  echo "Docker Containers:"
  docker ps --filter "name=nettools-" --format "table {{.Names}}\t{{.Status}}"
  
  # Check custom services
  echo -e "\nCustom Services:"
  if systemctl is-active --quiet nettools-api-gateway.service 2>/dev/null; then
    echo "API Gateway:    [ RUNNING ]"
  else
    echo "API Gateway:    [ STOPPED ]"
  fi
  
  # Add more services as they are installed
  
  echo
}

start_services() {
  log_section "Starting NetTools services"
  
  log_info "Starting Docker services"
  if [ -f "${DOCKER_DIR}/docker-compose.yml" ]; then
    cd "${DOCKER_DIR}" && docker compose up -d
  else
    log_warning "Docker Compose file not found at ${DOCKER_DIR}/docker-compose.yml"
  fi
  
  log_info "Starting custom services"
  if systemctl list-unit-files | grep -q "nettools-api-gateway.service"; then
    systemctl start nettools-api-gateway.service
  fi
  
  # Add more services as they are installed
  
  check_status
}

stop_services() {
  log_section "Stopping NetTools services"
  
  log_info "Stopping custom services"
  if systemctl list-unit-files | grep -q "nettools-api-gateway.service"; then
    systemctl stop nettools-api-gateway.service
  fi
  
  log_info "Stopping Docker services"
  if [ -f "${DOCKER_DIR}/docker-compose.yml" ]; then
    cd "${DOCKER_DIR}" && docker compose down
  else
    log_warning "Docker Compose file not found at ${DOCKER_DIR}/docker-compose.yml"
  fi
  
  check_status
}

restart_services() {
  log_section "Restarting NetTools services"
  
  stop_services
  start_services
}

# Main execution
case "$1" in
  start)
    start_services
    ;;
  stop)
    stop_services
    ;;
  restart)
    restart_services
    ;;
  status)
    check_status
    ;;
  *)
    usage
    ;;
esac
EOL
  
  chmod 0755 "${SCRIPT_DIR}/nettools-control.sh"
  chown "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "${SCRIPT_DIR}/nettools-control.sh"
  
  log_info "Creating update script"
  cat > "${SCRIPT_DIR}/nettools-update.sh" << 'EOL'
#!/bin/bash
# nettools-update.sh
# Update NetTools platform

INSTALL_DIR=${NETTOOLS_HOME:-"/opt/nettools"}
SCRIPT_DIR="${INSTALL_DIR}/scripts"

# Source common functions
source "${SCRIPT_DIR}/lib/common.sh"

log_section "Updating NetTools Platform"

# Update system packages
log_info "Updating system packages"
apt-get update && apt-get upgrade -y

# Update Node.js packages
for module in "${INSTALL_DIR}/modules"/*; do
  if [ -d "${module}" ] && [ -f "${module}/package.json" ]; then
    log_info "Updating Node.js packages in $(basename "${module}")"
    cd "${module}" && npm update
  fi
done

# Restart services
log_info "Restarting services"
"${SCRIPT_DIR}/nettools-control.sh" restart

log_success "NetTools Platform update completed"
EOL
  
  chmod 0755 "${SCRIPT_DIR}/nettools-update.sh"
  chown "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "${SCRIPT_DIR}/nettools-update.sh"
  
  log_success "Helper scripts created successfully"
  return 0
}

# Verify installation
verify_installation() {
  log_section "Verifying environment setup"
  
  local errors=0
  
  # Check Docker
  if command_exists docker; then
    log_success "Docker is installed: $(docker --version)"
  else
    log_error "Docker installation failed"
    errors=$((errors + 1))
  fi
  
  # Check Node.js
  if command_exists node; then
    log_success "Node.js is installed: $(node --version)"
  else
    log_error "Node.js installation failed"
    errors=$((errors + 1))
  fi
  
  # Check user
  if id "${NETTOOLS_USER}" &>/dev/null; then
    log_success "NetTools user ${NETTOOLS_USER} exists"
  else
    log_error "NetTools user creation failed"
    errors=$((errors + 1))
  fi
  
  # Check directory structure
  if [ -d "${INSTALL_DIR}" ] && [ -d "${MODULES_DIR}" ] && [ -d "${DOCKER_DIR}" ]; then
    log_success "Directory structure is correct"
  else
    log_error "Directory structure creation failed"
    errors=$((errors + 1))
  fi
  
  if [ $errors -eq 0 ]; then
    log_success "Environment setup completed successfully"
    return 0
  else
    log_error "Environment setup completed with ${errors} errors"
    return 1
  fi
}

# Main function
main() {
  # Check if script is run as root
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    exit 1
  fi
  
  log_section "Starting NetTools environment setup"
  
  # Execute setup steps
  check_system_requirements || exit 1
  update_packages || exit 1
  install_docker || exit 1
  install_nodejs || exit 1
  setup_user || exit 1
  create_directory_structure || exit 1
  setup_environment_variables || exit 1
  create_helper_scripts || exit 1
  
  # Verify installation
  verify_installation
  
  log_section "NetTools environment setup completed"
}

# Execute main function
main
