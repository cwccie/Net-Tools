#!/bin/bash
# common.sh
# Shared functions for NetTools Platform installation scripts

# Ensure the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This script should be sourced, not executed directly."
  echo "Usage: source ${BASH_SOURCE[0]}"
  exit 1
fi

# Default variables if not already defined
INSTALL_DIR=${INSTALL_DIR:-"/opt/nettools"}
LOG_DIR=${LOG_DIR:-"${INSTALL_DIR}/logs"}
CONFIG_DIR=${CONFIG_DIR:-"${INSTALL_DIR}/config"}
SCRIPT_DIR=${SCRIPT_DIR:-"${INSTALL_DIR}/scripts"}
LOG_FILE=${LOG_FILE:-"${LOG_DIR}/install.log"}
CONFIG_FILE=${CONFIG_FILE:-"${CONFIG_DIR}/setup.conf"}

# Ensure log directory exists
mkdir -p "${LOG_DIR}" 2>/dev/null || true

# Color definitions for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1${NC}" | tee -a "${LOG_FILE}"
}

log_success() {
  echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
  echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
  echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1${NC}" | tee -a "${LOG_FILE}"
}

log_section() {
  echo -e "\n${BLUE}$(date '+%Y-%m-%d %H:%M:%S') [SECTION] ===== $1 =====${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
  log_error "$1"
  if [ "${2:-}" == "exit" ]; then
    exit 1
  fi
}

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
  return $?
}

# Check service health with configurable retries
check_service_health() {
  local service_name="$1"
  local url="$2"
  local max_attempts="${3:-10}"
  local wait_seconds="${4:-3}"
  
  log_info "Checking health of $service_name at $url"
  
  for ((i=1; i<=max_attempts; i++)); do
    if curl -s "$url" > /dev/null; then
      log_success "✅ $service_name is healthy"
      return 0
    else
      log_warning "⏳ Waiting for $service_name to become healthy ($i/$max_attempts)"
      sleep "$wait_seconds"
    fi
  done
  
  log_error "❌ $service_name health check failed after $max_attempts attempts"
  return 1
}

# Wait for Docker container to be ready
wait_for_container() {
  local container_name="$1"
  local max_attempts="${2:-30}"
  local wait_seconds="${3:-2}"
  
  log_info "Waiting for container $container_name to be ready"
  
  for ((i=1; i<=max_attempts; i++)); do
    if docker ps | grep -q "$container_name"; then
      log_success "✅ Container $container_name is running"
      return 0
    else
      log_warning "⏳ Waiting for container $container_name to start ($i/$max_attempts)"
      sleep "$wait_seconds"
    fi
  done
  
  log_error "❌ Container $container_name failed to start after $max_attempts attempts"
  return 1
}

# Wait for database to be available
wait_for_db() {
  local host="$1"
  local port="$2"
  local user="$3"
  local db_name="$4"
  local max_attempts="${5:-30}"
  local wait_seconds="${6:-2}"
  
  log_info "Waiting for database $db_name to be ready on $host:$port"
  
  for ((i=1; i<=max_attempts; i++)); do
    if docker exec -i nettools-timescaledb pg_isready -h "$host" -p "$port" -U "$user" -d "$db_name" > /dev/null 2>&1; then
      log_success "✅ Database $db_name is ready"
      return 0
    else
      log_warning "⏳ Waiting for database $db_name to be ready ($i/$max_attempts)"
      sleep "$wait_seconds"
    fi
  done
  
  log_error "❌ Database $db_name failed to become ready after $max_attempts attempts"
  return 1
}

# Create directory with proper permissions
create_directory() {
  local dir="$1"
  local owner="${2:-$(whoami)}"
  local group="${3:-$(whoami)}"
  local perms="${4:-0750}"
  
  if [ ! -d "$dir" ]; then
    log_info "Creating directory $dir"
    mkdir -p "$dir" || { handle_error "Failed to create directory $dir" "exit"; return 1; }
  else
    log_info "Directory $dir already exists"
  fi
  
  log_info "Setting permissions on $dir to $perms, owner: $owner, group: $group"
  chmod "$perms" "$dir" || { handle_error "Failed to set permissions on $dir"; return 1; }
  chown "$owner:$group" "$dir" || { handle_error "Failed to set ownership on $dir"; return 1; }
  
  return 0
}

# Check if a directory is writable
check_writable() {
  local dir="$1"
  
  if [ ! -d "$dir" ]; then
    log_error "Directory $dir does not exist"
    return 1
  fi
  
  if [ ! -w "$dir" ]; then
    log_error "Directory $dir is not writable"
    return 1
  fi
  
  return 0
}

# Load configuration from file
load_config() {
  local config_file="$1"
  
  if [ ! -f "$config_file" ]; then
    log_error "Configuration file $config_file does not exist"
    return 1
  fi
  
  log_info "Loading configuration from $config_file"
  source "$config_file"
  
  return 0
}

# Create a backup of a file
backup_file() {
  local file="$1"
  local backup_dir="${2:-${INSTALL_DIR}/backups}"
  
  if [ ! -f "$file" ]; then
    log_warning "File $file does not exist, nothing to backup"
    return 0
  fi
  
  # Create backup directory if it doesn't exist
  mkdir -p "$backup_dir" || { handle_error "Failed to create backup directory $backup_dir"; return 1; }
  
  local backup_file="${backup_dir}/$(basename "$file").$(date '+%Y%m%d-%H%M%S')"
  log_info "Creating backup of $file to $backup_file"
  cp "$file" "$backup_file" || { handle_error "Failed to backup $file"; return 1; }
  
  return 0
}

# Check system resources
check_system_resources() {
  local min_ram="${1:-4096}" # 4GB in MB
  local min_disk="${2:-10240}" # 10GB in MB
  local min_cpu="${3:-2}"
  
  log_info "Checking system resources"
  
  # Check RAM
  local total_ram=$(free -m | awk '/^Mem:/{print $2}')
  if [ "$total_ram" -lt "$min_ram" ]; then
    log_warning "System has less than ${min_ram}MB RAM (${total_ram}MB). This may affect performance."
  else
    log_info "RAM check passed: ${total_ram}MB available"
  fi
  
  # Check disk space
  local install_disk_free=$(df -m "$INSTALL_DIR" | awk 'NR==2 {print $4}')
  if [ "$install_disk_free" -lt "$min_disk" ]; then
    log_warning "Less than ${min_disk}MB free disk space on installation directory (${install_disk_free}MB). This may cause issues."
  else
    log_info "Disk space check passed: ${install_disk_free}MB available"
  fi
  
  # Check CPU cores
  local cpu_cores=$(nproc)
  if [ "$cpu_cores" -lt "$min_cpu" ]; then
    log_warning "System has less than ${min_cpu} CPU cores (${cpu_cores}). This may affect performance."
  else
    log_info "CPU check passed: ${cpu_cores} cores available"
  fi
}

# Print a summary of the current system
print_system_summary() {
  log_section "System Summary"
  
  # OS Information
  echo "OS: $(lsb_release -d | cut -f2)" | tee -a "${LOG_FILE}"
  echo "Kernel: $(uname -r)" | tee -a "${LOG_FILE}"
  
  # Hardware
  echo "CPU: $(nproc) cores" | tee -a "${LOG_FILE}"
  echo "RAM: $(free -h | awk '/^Mem:/{print $2}')" | tee -a "${LOG_FILE}"
  echo "Disk: $(df -h "$INSTALL_DIR" | awk 'NR==2 {print $4}') free" | tee -a "${LOG_FILE}"
  
  # Network
  echo "Hostname: $(hostname)" | tee -a "${LOG_FILE}"
  echo "IP Address: $(hostname -I | awk '{print $1}')" | tee -a "${LOG_FILE}"
  
  # User
  echo "Current User: $(whoami)" | tee -a "${LOG_FILE}"
  
  log_section "End of System Summary"
}

# Check if we are running with required privileges
check_privileges() {
  if [[ $EUID -ne 0 ]] && ! groups | grep -q '\bsudo\b'; then
    log_error "This script must be run as root or by a user with sudo privileges"
    return 1
  fi
  
  return 0
}

# Prompt for user confirmation
confirm() {
  local prompt="${1:-Are you sure you want to continue?}"
  local default="${2:-Y}"
  
  while true; do
    if [ "$default" = "Y" ]; then
      read -p "$prompt [Y/n]: " response
      response=${response:-Y}
    else
      read -p "$prompt [y/N]: " response
      response=${response:-N}
    fi
    
    case $response in
      [Yy]* ) return 0 ;;
      [Nn]* ) return 1 ;;
      * ) echo "Please answer yes (Y) or no (N)." ;;
    esac
  done
}

# Export functions that need to be available to other scripts
export -f log_info log_success log_error log_warning log_section
export -f handle_error command_exists check_service_health wait_for_container
export -f create_directory check_writable load_config backup_file
export -f check_system_resources print_system_summary check_privileges confirm
export -f wait_for_db
