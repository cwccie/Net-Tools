# Net-Tools

A distributed, modular network monitoring and management platform that scales from single-node deployments to large multi-node clusters while maintaining a unified user experience.

## Problem

Enterprise network operations teams need monitoring infrastructure that grows with their environment. Most open-source solutions either work for small labs or require complex orchestration for large deployments — rarely both. Net-Tools bridges that gap with a modular architecture where each component can run standalone or as part of a coordinated cluster.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Net-Tools Platform              │
├────────────┬────────────┬───────────────────────┤
│ Environment│    Core    │   Management Layer    │
│   Setup    │ Infra      │                       │
│            │            │  - Monitoring          │
│ - System   │ - Docker   │  - Alerting            │
│   config   │ - Netdata  │  - Visualization       │
│ - Network  │ - Cockpit  │  - Device management   │
│   tuning   │ - WebUI    │                       │
└────────────┴────────────┴───────────────────────┘
```

**Components:**
- **Environment Setup** (`1-environment-setup.sh`) — System prerequisites, network tuning, security hardening
- **Core Infrastructure** (`2-core-infrastructure.sh`) — Docker, Netdata, Cockpit, and monitoring stack deployment
- **Master Setup** (`master-setup.sh`) — Orchestrates full deployment across nodes
- **Common Utilities** (`common-sh.sh`) — Shared functions for logging, validation, error handling

## Quick Start

```bash
# Download the installer
curl -O https://raw.githubusercontent.com/cwccie/Net-Tools/main/nettools-installer.sh

# Make executable and run
chmod +x nettools-installer.sh
sudo ./nettools-installer.sh
```

For multi-node deployments, use the master setup:

```bash
git clone https://github.com/cwccie/Net-Tools.git
cd Net-Tools
sudo ./master-setup.sh
```

## Features

- **Single-command deployment** — One script installs the full monitoring stack
- **Modular design** — Run individual components or the full platform
- **Multi-node scaling** — Extend from single server to distributed cluster
- **Infrastructure monitoring** — Real-time metrics via Netdata
- **Web management** — Server administration via Cockpit
- **Container orchestration** — Docker-based service management

## Requirements

- Ubuntu 20.04+ / Debian 11+
- Root or sudo access
- Minimum 2GB RAM, 20GB disk

## File Structure

```
Net-Tools/
├── nettools-installer.sh          # Quick-start single-node installer
├── master-setup.sh                # Full multi-node orchestrator
├── 1-environment-setup.sh         # System prerequisites and tuning
├── 2-core-infrastructure.sh       # Docker, Netdata, Cockpit deployment
├── common-sh.sh                   # Shared utility functions
└── README.md
```

## License

MIT License — see [LICENSE](LICENSE)
