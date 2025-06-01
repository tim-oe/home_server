# Home Server Setup Guide

## Initial Setup

### System Requirements
- Linux-based system (tested on Ubuntu with kernel 6.8.0-60-generic)
- Docker and Docker Compose installed
- Gradle build system
- SSH server
- Sufficient storage for services and backups

### Prerequisites Installation

1. **Docker Installation**
   ```bash
   # Update package index
   sudo apt update
   
   # Install required packages
   sudo apt install -y docker.io docker-compose
   
   # Add current user to docker group
   sudo usermod -aG docker $USER
   ```

2. **Gradle Setup**
   - Project includes Gradle wrapper (gradlew)
   - No additional installation needed
   - Use `./gradlew` for all Gradle commands

3. **Network Prerequisites**
   ```bash
   # Create shared Docker network
   ./gradlew dockerNet
   ```

## Service Deployment

### Initial Configuration

1. **Directory Structure Setup**
   ```bash
   # Initialize service directories and permissions
   ./gradlew initAcl
   
   # Deploy maintenance scripts
   ./gradlew deployScripts
   
   # Deploy cron jobs
   ./gradlew deployCron
   ```

2. **SSL Certificate Setup**
   - Configure Cloudflare DNS settings
   - Set up Certbot with Cloudflare plugin
   - Generate initial certificates

### Core Services Deployment

1. **Build Tools**
   - Jenkins
   - Nexus
   - SonarQube
   Refer to `src/services/build/` for specific configurations

2. **Monitoring Stack**
   - Grafana
   - InfluxDB
   - Telegraf
   Refer to `src/services/monitoring/` for specific configurations

3. **Network Services**
   - NGINX reverse proxy
   - Unifi Controller
   Refer to `src/services/network/` for specific configurations

### Backup Configuration

1. **Local Backup Setup**
   ```bash
   # Configure docker-volume-backup
   # Edit backup configuration in src/services/backup/docker-compose.yml
   ```

2. **Cloud Backup Setup**
   ```bash
   # Configure rclone
   rclone config
   
   # Test configuration
   rclone ls remote:backup
   ```

## Security Configuration

### Access Control

1. **User Management**
   ```bash
   # Set up ansible user
   sudo useradd -m ansible
   sudo usermod -aG docker ansible
   
   # Configure SSH keys
   sudo mkdir -p /home/ansible/.ssh
   sudo cp ansible.pub /home/ansible/.ssh/authorized_keys
   sudo chown -R ansible:ansible /home/ansible/.ssh
   sudo chmod 700 /home/ansible/.ssh
   sudo chmod 600 /home/ansible/.ssh/authorized_keys
   ```

2. **Service Security**
   - Configure Vaultwarden
   - Set up SSL certificates
   - Configure network security

### Network Security

1. **Firewall Configuration**
   ```bash
   # Configure UFW
   sudo ufw allow ssh
   sudo ufw allow http
   sudo ufw allow https
   sudo ufw enable
   ```

2. **Reverse Proxy Setup**
   - Configure NGINX
   - Set up SSL termination
   - Configure security headers

## Maintenance Procedures

### Regular Maintenance

1. **Backup Verification**
   ```bash
   # Verify local backups
   ls -l /mnt/raid/backups
   
   # Verify cloud backups
   rclone ls remote:backup
   ```

2. **System Updates**
   ```bash
   # Update containers
   docker-compose pull
   docker-compose up -d
   
   # Clean up old images
   docker image prune
   ```

### Monitoring

1. **Service Health Checks**
   - Monitor Grafana dashboards
   - Check service logs
   - Verify backup completion

2. **Performance Monitoring**
   - Monitor system resources
   - Check container resource usage
   - Monitor network performance

## Troubleshooting

### Common Issues

1. **Container Issues**
   ```bash
   # Check container status
   docker ps -a
   
   # View container logs
   docker logs <container_name>
   
   # Restart container
   docker-compose restart <service_name>
   ```

2. **Network Issues**
   ```bash
   # Check Docker network
   docker network ls
   docker network inspect share-net
   
   # Verify NGINX configuration
   nginx -t
   ```

3. **Volume Issues**
   ```bash
   # List volumes
   docker volume ls
   
   # Inspect volume
   docker volume inspect <volume_name>
   ```

## Upgrade Procedures

### Service Upgrades

1. **Preparation**
   - Backup all data
   - Review changelog
   - Plan maintenance window

2. **Upgrade Process**
   ```bash
   # Pull new images
   docker-compose pull
   
   # Apply upgrades
   docker-compose up -d
   
   # Verify services
   docker-compose ps
   ```

### System Upgrades

1. **OS Updates**
   ```bash
   # Update system packages
   sudo apt update
   sudo apt upgrade
   
   # Verify services after update
   docker-compose ps
   ```

2. **Docker Updates**
   ```bash
   # Update Docker
   sudo apt update
   sudo apt upgrade docker.io docker-compose
   
   # Restart Docker
   sudo systemctl restart docker
   ``` 