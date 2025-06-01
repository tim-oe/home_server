# Home Server Project Overview

## Introduction
This project implements a comprehensive home lab cloud-like setup for development and learning purposes. It provides a suite of self-hosted services including continuous integration, monitoring, network management, and home automation tools.

## System Architecture

### Core Components
1. **Build & Development Tools**
   - Jenkins: Continuous Integration/Continuous Deployment server
   - Nexus: Repository manager for artifacts
   - SonarQube: Code quality and security analysis

2. **Monitoring Stack**
   - Grafana: Visualization and analytics
   - InfluxDB: Time series database
   - Telegraf: Server agent for collecting metrics

3. **Network Management**
   - Unifi WAP Controller: Wireless Access Point management
   - NGINX: Reverse proxy server
   - Certbot: SSL certificate automation with Cloudflare DNS

4. **Security & Access**
   - Vaultwarden: Password management system
   - SSL/TLS encryption via Certbot

5. **Infrastructure Management**
   - Portainer: Docker container management
   - Docker Volume Backup: Data persistence and backup solution

6. **Home Automation**
   - OpenHAB: Home automation platform (Work in Progress)

## Backup Strategy

### Two-Tier Backup System
1. **Local Backup**
   - Implementation: docker-volume-backup
   - Target: Local NAS storage
   - Purpose: Quick recovery and local redundancy

2. **Cloud Backup**
   - Implementation: rclone
   - Configuration: `/root/.config/rclone/rclone.conf`
   - Purpose: Off-site disaster recovery

## Network Architecture

### KVM Configuration
- Bridged network setup using NetworkManager
- Custom bridge network configuration for KVM
- Detailed setup instructions available in project documentation

## Development Environment

### Build System
- Gradle-based build system
- Spotless for code formatting
- SSH deployment capabilities
- Docker network management

### Directory Structure
```
home_server/
├── src/
│   ├── services/    # Service configurations
│   ├── bin/         # Binary and script files
│   ├── docker/      # Docker-related configurations
│   ├── etc/         # System configurations
│   ├── home/        # Home directory configurations
├── docs/            # Project documentation
└── build.gradle     # Build configuration
```

## Deployment

### Prerequisites
- Linux environment (tested on 6.8.0-60-generic)
- Docker and Docker Compose
- Gradle build system
- SSH access for deployment

### Access Control
- Managed through ACL (Access Control Lists)
- Ansible user permissions for service deployment
- Specific directory permissions for service operations

## Planned Enhancements
1. **Monitoring Improvements**
   - Container monitoring dashboard
   - Enhanced Grafana/Telegraf integration

2. **Security Enhancements**
   - Implementation of Authentik
   - SMTP relay setup

3. **Network Services**
   - Pi-hole DNS management
   - Nginx Proxy Manager implementation
   - Uptime-Kuma monitoring

4. **Infrastructure Management**
   - Netbox implementation
   - RustDesk self-hosted solution
   - Speedtest-tracker integration

## Maintenance

### Common Operations
1. **Container Management**
   ```bash
   # Get volume mappings
   docker inspect --type container -f '{{range $i, $v := .Mounts }}{{printf "%v\n" $v}}{{end}}' <container_id>

   # Access container shell
   docker exec -it <container name> /bin/bash

   # Create compose-compatible volume
   docker volume create --name "vol_name" --label "com.docker.compose.project=container_name"
   ```

2. **Volume Management**
   - Regular backup verification
   - Multi-volume backup strategy
   - Restore procedures documented

### Troubleshooting
- Container access procedures
- Volume management commands
- Network debugging steps

## References
- Docker Compose documentation
- Service-specific documentation links
- Configuration templates and examples 