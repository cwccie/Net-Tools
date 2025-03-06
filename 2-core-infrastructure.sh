#!/bin/bash
# 2-core-infrastructure.sh
# Setup core infrastructure services for NetTools Platform

# Exit on any error
set -e

# Set script directory as current directory's parent if not provided
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "${SCRIPT_PATH}")"
SCRIPT_DIR="${INSTALL_DIR}/scripts"
LOG_DIR="${INSTALL_DIR}/logs"
CONFIG_DIR="${INSTALL_DIR}/config"
DOCKER_DIR="${INSTALL_DIR}/docker"
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

# Check if environment is set up correctly
check_environment() {
  log_section "Checking environment"
  
  if ! command_exists docker; then
    log_error "Docker is not installed. Please run the environment setup script first."
    return 1
  fi
  
  if ! command_exists docker-compose && ! command_exists "docker compose"; then
    log_error "Docker Compose is not installed. Please run the environment setup script first."
    return 1
  fi
  
  # Check if Docker is running
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not running. Please start Docker service."
    return 1
  }
  
  # Check for required directories
  if [ ! -d "${DOCKER_DIR}" ]; then
    log_error "Docker directory ${DOCKER_DIR} does not exist."
    return 1
  fi
  
  log_success "Environment is set up correctly"
  return 0
}

# Create Docker network
create_docker_network() {
  log_section "Creating Docker network"
  
  # Check if network already exists
  if docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1; then
    log_info "Docker network ${DOCKER_NETWORK} already exists"
    return 0
  fi
  
  log_info "Creating Docker network ${DOCKER_NETWORK} with subnet ${DOCKER_SUBNET}"
  docker network create --subnet="${DOCKER_SUBNET}" "${DOCKER_NETWORK}" || {
    log_error "Failed to create Docker network"
    return 1
  }
  
  log_success "Docker network created successfully"
  return 0
}

# Create Docker Compose file
create_docker_compose() {
  log_section "Creating Docker Compose configuration"
  
  local compose_dir="${DOCKER_DIR}/development"
  local compose_file="${compose_dir}/docker-compose.yml"
  
  # Create necessary directories
  create_directory "${compose_dir}/volumes/timescaledb" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${compose_dir}/volumes/redis" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${compose_dir}/volumes/vault" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${compose_dir}/volumes/prometheus" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${compose_dir}/volumes/grafana" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${compose_dir}/config/prometheus" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  create_directory "${compose_dir}/config/grafana" "${NETTOOLS_USER}" "${NETTOOLS_GROUP}" "0755"
  
  # Create Docker Compose file
  log_info "Creating docker-compose.yml at ${compose_file}"
  
  cat > "${compose_file}" << EOL
version: '3.8'

services:
  timescaledb:
    image: timescale/timescaledb:latest-pg14
    container_name: nettools-timescaledb
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=${DB_NAME}
    volumes:
      - ./volumes/timescaledb:/var/lib/postgresql/data
    ports:
      - "${TIMESCALEDB_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - nettools-network

  redis:
    image: redis:6.2-alpine
    container_name: nettools-redis
    restart: unless-stopped
    command: redis-server --save 60 1 --loglevel warning
    volumes:
      - ./volumes/redis:/data
    ports:
      - "${REDIS_PORT}:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - nettools-network

  vault:
    image: hashicorp/vault:latest
    container_name: nettools-vault
    restart: unless-stopped
    ports:
      - "${VAULT_PORT}:8200"
    environment:
      - VAULT_DEV_ROOT_TOKEN_ID=nettools-dev-token
      - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
    cap_add:
      - IPC_LOCK
    command: server -dev
    volumes:
      - ./volumes/vault:/vault/data
    healthcheck:
      test: ["CMD", "vault", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - nettools-network

  prometheus:
    image: prom/prometheus:latest
    container_name: nettools-prometheus
    restart: unless-stopped
    volumes:
      - ./config/prometheus:/etc/prometheus
      - ./volumes/prometheus:/prometheus
    ports:
      - "${PROMETHEUS_PORT}:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - nettools-network

  grafana:
    image: grafana/grafana:latest
    container_name: nettools-grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./volumes/grafana:/var/lib/grafana
    ports:
      - "${GRAFANA_PORT}:3000"
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - nettools-network

  frontend-dev:
    image: node:20-alpine
    container_name: nettools-frontend-dev
    volumes:
      - ${INSTALL_DIR}:/app
    working_dir: /app
    ports:
      - "3000:3000"
    tty: true
    command: tail -f /dev/null
    networks:
      - nettools-network

  backend-dev:
    image: node:20-alpine
    container_name: nettools-backend-dev
    volumes:
      - ${INSTALL_DIR}:/app
    working_dir: /app
    ports:
      - "9001:9001"
    tty: true
    command: tail -f /dev/null
    networks:
      - nettools-network

networks:
  nettools-network:
    external: true
EOL

  # Create Prometheus configuration
  log_info "Creating Prometheus configuration"
  cat > "${compose_dir}/config/prometheus/prometheus.yml" << EOL
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'auth-service'
    static_configs:
      - targets: ['backend-dev:9001']

  - job_name: 'api-gateway'
    static_configs:
      - targets: ['backend-dev:9000']
EOL

  # Set proper permissions
  chmod 0644 "${compose_file}"
  chmod 0644 "${compose_dir}/config/prometheus/prometheus.yml"
  chown -R "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "${compose_dir}"
  
  log_success "Docker Compose configuration created successfully"
  return 0
}

# Start infrastructure services
start_infrastructure_services() {
  log_section "Starting infrastructure services"
  
  local compose_dir="${DOCKER_DIR}/development"
  
  log_info "Starting Docker Compose services"
  cd "${compose_dir}" && docker compose up -d || {
    log_error "Failed to start Docker Compose services"
    return 1
  }
  
  log_success "Infrastructure services started successfully"
  return 0
}

# Wait for services to be ready
wait_for_services_ready() {
  log_section "Waiting for services to be ready"
  
  # Wait for TimescaleDB
  log_info "Waiting for TimescaleDB to be ready"
  wait_for_db "localhost" "${TIMESCALEDB_PORT}" "${DB_USER}" "${DB_NAME}" 30 2 || {
    log_error "TimescaleDB failed to become ready"
    return 1
  }
  
  # Wait for Redis
  log_info "Waiting for Redis to be ready"
  wait_for_container "nettools-redis" 30 2 || {
    log_error "Redis failed to become ready"
    return 1
  }
  
  # Wait for Vault
  log_info "Waiting for Vault to be ready"
  wait_for_container "nettools-vault" 30 2 || {
    log_error "Vault failed to become ready"
    return 1
  }
  
  # Wait for Prometheus
  log_info "Waiting for Prometheus to be ready"
  wait_for_container "nettools-prometheus" 30 2 || {
    log_error "Prometheus failed to become ready"
    return 1
  }
  
  # Wait for Grafana
  log_info "Waiting for Grafana to be ready"
  wait_for_container "nettools-grafana" 30 2 || {
    log_error "Grafana failed to become ready"
    return 1
  }
  
  log_success "All services are ready"
  return 0
}

# Initialize database
initialize_database() {
  log_section "Initializing database"
  
  log_info "Creating initial database structure"
  
  # Create SQL initialization file
  local sql_init_file="${DOCKER_DIR}/development/init-db.sql"
  
  cat > "${sql_init_file}" << EOL
-- NetTools Database Initialization

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "timescaledb";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS "auth";
CREATE SCHEMA IF NOT EXISTS "monitoring";
CREATE SCHEMA IF NOT EXISTS "device";
CREATE SCHEMA IF NOT EXISTS "netflow";
CREATE SCHEMA IF NOT EXISTS "capture";

-- Set search path
SET search_path TO "auth", "monitoring", "device", "netflow", "capture", "public";

-- Create users table
CREATE TABLE IF NOT EXISTS "auth"."users" (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username VARCHAR(255) NOT NULL UNIQUE,
  email VARCHAR(255) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  "firstName" VARCHAR(255),
  "lastName" VARCHAR(255),
  role VARCHAR(50) NOT NULL DEFAULT 'user',
  "isActive" BOOLEAN DEFAULT TRUE,
  "lastLogin" TIMESTAMP,
  "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
  "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW(),
  "deletedAt" TIMESTAMP
);

-- Create refresh tokens table
CREATE TABLE IF NOT EXISTS "auth"."refresh_tokens" (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  token VARCHAR(255) NOT NULL UNIQUE,
  "userId" UUID NOT NULL REFERENCES "auth"."users"(id) ON DELETE CASCADE,
  "expiresAt" TIMESTAMP NOT NULL,
  "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
  "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Initial admin user (password: adminpassword)
INSERT INTO "auth"."users" (username, email, password, role)
VALUES (
  'admin',
  'admin@nettools.local',
  '$2b$10$3euPcuTQH/EXnbmUk/9sYOLEQGjwgEBZTpdfaFcvwCJKZPQQxl9X2',
  'admin'
) ON CONFLICT (username) DO NOTHING;
EOL

  # Execute SQL file in the database container
  log_info "Running database initialization script"
  docker exec -i nettools-timescaledb psql -U "${DB_USER}" -d "${DB_NAME}" < "${sql_init_file}" || {
    log_error "Failed to initialize database"
    return 1
  }
  
  # Cleanup
  rm "${sql_init_file}"
  
  log_success "Database initialized successfully"
  return 0
}

# Configure Redis
configure_redis() {
  log_section "Configuring Redis"
  
  log_info "Setting up Redis configuration"
  
  # Create Redis config file
  local redis_conf="${DOCKER_DIR}/development/config/redis.conf"
  
  mkdir -p "$(dirname "${redis_conf}")"
  
  cat > "${redis_conf}" << EOL
# Redis configuration for NetTools Platform
maxmemory 512mb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
EOL

  # Restart Redis with the new configuration
  log_info "Applying Redis configuration"
  docker restart nettools-redis || {
    log_error "Failed to restart Redis"
    return 1
  }
  
  log_success "Redis configured successfully"
  return 0
}

# Set up HashiCorp Vault
setup_vault() {
  log_section "Setting up HashiCorp Vault"
  
  log_info "Initializing Vault"
  
  # Wait for Vault to be ready
  sleep 5
  
  # Check if Vault is already initialized
  if docker exec -i nettools-vault vault status 2>/dev/null | grep -q "Initialized.*true"; then
    log_info "Vault is already initialized"
  else
    log_warning "Vault initialization would normally be required in production"
    log_info "Using development mode with predefined root token: nettools-dev-token"
  fi
  
  # Create a simple script to set up Vault policies and secrets
  log_info "Setting up Vault policies"
  
  local vault_script="${DOCKER_DIR}/development/setup-vault.sh"
  
  cat > "${vault_script}" << 'EOL'
#!/bin/sh
# Setup Vault policies and secrets for NetTools Platform

# Set Vault address and token
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="nettools-dev-token"

# Create policies
vault policy write nettools-auth - << EOF
path "secret/data/nettools/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

vault policy write nettools-api - << EOF
path "secret/data/nettools/api/*" {
  capabilities = ["read", "list"]
}
EOF

# Enable the KV secrets engine
vault secrets enable -path=secret -version=2 kv

# Store some initial secrets
vault kv put secret/nettools/auth/jwt secret="change-this-in-production" issuer="nettools"
vault kv put secret/nettools/auth/database user="nettools" password="nettools"

echo "Vault setup completed successfully"
EOL

  chmod +x "${vault_script}"
  
  # Execute the script
  log_info "Running Vault setup script"
  "${vault_script}" || {
    log_error "Failed to set up Vault"
    return 1
  }
  
  # Cleanup
  rm "${vault_script}"
  
  log_success "Vault set up successfully"
  return 0
}

# Configure monitoring stack
setup_monitoring() {
  log_section "Setting up monitoring stack"
  
  # Configure Grafana datasources
  log_info "Configuring Grafana datasources"
  
  local grafana_ds_dir="${DOCKER_DIR}/development/config/grafana/provisioning/datasources"
  mkdir -p "${grafana_ds_dir}"
  
  cat > "${grafana_ds_dir}/prometheus.yml" << EOL
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOL

  # Configure Grafana dashboards
  log_info "Setting up Grafana dashboards"
  
  local grafana_dash_dir="${DOCKER_DIR}/development/config/grafana/provisioning/dashboards"
  mkdir -p "${grafana_dash_dir}"
  
  cat > "${grafana_dash_dir}/dashboards.yml" << EOL
apiVersion: 1

providers:
  - name: 'NetTools'
    orgId: 1
    folder: 'NetTools'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOL

  # Create a simple dashboard
  local grafana_dash_path="${DOCKER_DIR}/development/volumes/grafana/dashboards"
  mkdir -p "${grafana_dash_path}"
  
  cat > "${grafana_dash_path}/nettools-overview.json" << EOL
{
  "annotations": {
    "list": []
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": 1,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 0.1,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "title": "NetTools Overview",
      "type": "timeseries"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": [
    "nettools"
  ],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "NetTools Overview",
  "version": 0,
  "weekStart": ""
}
EOL

  # Set proper permissions
  chown -R "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "${DOCKER_DIR}/development/config"
  chown -R "${NETTOOLS_USER}:${NETTOOLS_GROUP}" "${DOCKER_DIR}/development/volumes/grafana"
  
  # Restart Grafana to apply changes
  log_info "Restarting Grafana to apply configuration"
  docker restart nettools-grafana || {
    log_error "Failed to restart Grafana"
    return 1
  }
  
  log_success "Monitoring stack set up successfully"
  return 0
}

# Verify infrastructure
verify_infrastructure() {
  log_section "Verifying infrastructure services"
  
  local errors=0
  
  # Check TimescaleDB
  if docker exec -i nettools-timescaledb pg_isready -U "${DB_USER}" > /dev/null 2>&1; then
    log_success "TimescaleDB is running and accessible"
  else
    log_error "TimescaleDB verification failed"
    errors=$((errors + 1))
  fi
  
  # Check Redis
  if docker exec -i nettools-redis redis-cli ping | grep -q "PONG"; then
    log_success "Redis is running and accessible"
  else
    log_error "Redis verification failed"
    errors=$((errors + 1))
  fi
  
  # Check Vault
  if docker exec -i nettools-vault vault status > /dev/null 2>&1; then
    log_success "Vault is running and accessible"
  else
    log_error "Vault verification failed"
    errors=$((errors + 1))
  fi
  
  # Check Prometheus
  if curl -s "http://localhost:${PROMETHEUS_PORT}/-/healthy" > /dev/null 2>&1; then
    log_success "Prometheus is running and accessible"
  else
    log_error "Prometheus verification failed"
    errors=$((errors + 1))
  fi
  
  # Check Grafana
  if curl -s "http://localhost:${GRAFANA_PORT}/api/health" > /dev/null 2>&1; then
    log_success "Grafana is running and accessible"
  else
    log_error "Grafana verification failed"
    errors=$((errors + 1))
  }
  
  if [ $errors -eq 0 ]; then
    log_success "All infrastructure services are running correctly"
    return 0
  else
    log_error "Infrastructure verification completed with ${errors} errors"
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
  
  log_section "Starting NetTools core infrastructure setup"
  
  # Execute setup steps
  check_environment || exit 1
  create_docker_network || exit 1
  create_docker_compose || exit 1
  start_infrastructure_services || exit 1
  wait_for_services_ready || exit 1
  initialize_database || exit 1
  configure_redis || exit 1
  setup_vault || exit 1
  setup_monitoring || exit 1
  
  # Verify infrastructure
  verify_infrastructure
  
  log_section "NetTools core infrastructure setup completed"
}

# Execute main function
main
