#!/bin/bash
# nettools-installer.sh
# Script to download, setup, and execute the NetTools installation scripts

# Exit on error
set -e

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo"
  exit 1
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "=================================================="
echo "    _   _      _   _____           _     "
echo "   | \ | | ___| |_|_   _|__   ___ | |___ "
echo "   |  \| |/ _ \ __|| |/ _ \ / _ \| / __|"
echo "   | |\  |  __/ |_ | | (_) | (_) | \__ \\"
echo "   |_| \_|\___|\__||_|\___/ \___/|_|___/"
echo "                                         "
echo "    Platform Installer from Git Repository"
echo "=================================================="
echo -e "${NC}"

# Installation variables
INSTALL_DIR="/opt/nettools"
TEMP_DIR="/tmp/nettools-git"
GIT_REPO="https://github.com/cwccie/Net-Tools.git"
NETTOOLS_USER="nettools"
NETTOOLS_GROUP="nettools"

# Create temp directory
echo -e "${BLUE}[INFO]${NC} Creating temporary directory for git clone"
rm -rf "${TEMP_DIR}" 2>/dev/null || true
mkdir -p "${TEMP_DIR}"

# Clone the repository
echo -e "${BLUE}[INFO]${NC} Cloning repository from ${GIT_REPO}"
git clone "${GIT_REPO}" "${TEMP_DIR}" || {
  echo -e "${RED}[ERROR]${NC} Failed to clone repository"
  exit 1
}

# Create target directory structure
echo -e "${BLUE}[INFO]${NC} Creating NetTools directory structure"
mkdir -p "${INSTALL_DIR}/scripts/lib" "${INSTALL_DIR}/logs" "${INSTALL_DIR}/config"

# Create nettools user if it doesn't exist
if ! getent group "${NETTOOLS_GROUP}" >/dev/null; then
  echo -e "${BLUE}[INFO]${NC} Creating group ${NETTOOLS_GROUP}"
  groupadd "${NETTOOLS_GROUP}"
fi

if ! id "${NETTOOLS_USER}" &>/dev/null; then
  echo -e "${BLUE}[INFO]${NC} Creating user ${NETTOOLS_USER}"
  useradd -m -g "${NETTOOLS_GROUP}" -s /bin/bash "${NETTOOLS_USER}"
fi

# Copy and set up scripts
echo -e "${BLUE}[INFO]${NC} Setting up script files"

# Check if script files exist in the repository
if [ -f "${TEMP_DIR}/scripts/lib/common.sh" ]; then
  # Copy from specific locations if scripts are already organized
  cp "${TEMP_DIR}/scripts/lib/common.sh" "${INSTALL_DIR}/scripts/lib/"
  cp "${TEMP_DIR}/master-setup.sh" "${INSTALL_DIR}/"
  cp "${TEMP_DIR}/scripts/1-environment-setup.sh" "${INSTALL_DIR}/scripts/"
  cp "${TEMP_DIR}/scripts/2-core-infrastructure.sh" "${INSTALL_DIR}/scripts/"
else
  # Otherwise, look for scripts in any location
  echo -e "${BLUE}[INFO]${NC} Searching for script files in the repository"
  
  # Find common.sh
  COMMON_SH=$(find "${TEMP_DIR}" -name "common.sh" -type f | head -n 1)
  if [ -z "${COMMON_SH}" ]; then
    echo -e "${RED}[ERROR]${NC} common.sh not found in repository"
    exit 1
  fi
  cp "${COMMON_SH}" "${INSTALL_DIR}/scripts/lib/"
  
  # Find master-setup.sh
  MASTER_SETUP=$(find "${TEMP_DIR}" -name "master-setup.sh" -type f | head -n 1)
  if [ -z "${MASTER_SETUP}" ]; then
    echo -e "${RED}[ERROR]${NC} master-setup.sh not found in repository"
    exit 1
  fi
  cp "${MASTER_SETUP}" "${INSTALL_DIR}/"
  
  # Find environment setup script
  ENV_SETUP=$(find "${TEMP_DIR}" -name "1-environment-setup.sh" -type f | head -n 1)
  if [ -z "${ENV_SETUP}" ]; then
    echo -e "${RED}[ERROR]${NC} 1-environment-setup.sh not found in repository"
    exit 1
  fi
  cp "${ENV_SETUP}" "${INSTALL_DIR}/scripts/"
  
  # Find core infrastructure script
  CORE_INFRA=$(find "${TEMP_DIR}" -name "2-core-infrastructure.sh" -type f | head -n 1)
  if [ -z "${CORE_INFRA}" ]; then
    echo -e "${RED}[ERROR]${NC} 2-core-infrastructure.sh not found in repository"
    exit 1
  fi
  cp "${CORE_INFRA}" "${INSTALL_DIR}/scripts/"
fi

# Set correct permissions
echo -e "${BLUE}[INFO]${NC} Setting script permissions"
chmod 755 "${INSTALL_DIR}/scripts/lib/common.sh"
chmod 755 "${INSTALL_DIR}/master-setup.sh"
chmod 755 "${INSTALL_DIR}/scripts/1-environment-setup.sh"
chmod 755 "${INSTALL_DIR}/scripts/2-core-infrastructure.sh"

# Set correct ownership
echo -e "${BLUE}[INFO]${NC} Setting ownership to ${NETTOOLS_USER}:${NETTOOLS_GROUP}"
chown -R "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "${INSTALL_DIR}"

# Clean up temp directory
echo -e "${BLUE}[INFO]${NC} Cleaning up temporary files"
rm -rf "${TEMP_DIR}"

# Execution options
echo -e "${GREEN}[SUCCESS]${NC} NetTools scripts have been set up at ${INSTALL_DIR}"
echo ""
echo "You can now run the master setup script:"
echo "  sudo ${INSTALL_DIR}/master-setup.sh"
echo ""
echo "Or run the individual scripts:"
echo "  sudo ${INSTALL_DIR}/scripts/1-environment-setup.sh"
echo "  sudo ${INSTALL_DIR}/scripts/2-core-infrastructure.sh"
echo ""

# Ask user if they want to run the installation now
read -p "Do you want to run the installation now? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}[INFO]${NC} Starting NetTools installation"
  "${INSTALL_DIR}/master-setup.sh"
else
  echo -e "${BLUE}[INFO]${NC} Installation not started. You can run it later with: sudo ${INSTALL_DIR}/master-setup.sh"
fi

echo -e "${GREEN}[COMPLETE]${NC} Script completed successfully"