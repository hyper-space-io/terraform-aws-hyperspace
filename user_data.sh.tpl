#!/bin/bash

# Set up logging
LOG_FILE="/var/log/ec2-setup.log"

# Function for logging
log() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

# Function for retry with error logging
retry() {
    local attempts=3
    local cmd="$@"
    local output
    for ((i=1; i<=attempts; i++)); do
        output=$($cmd 2>&1)
        if [ $? -eq 0 ]; then
            return 0
        else
            log "Command '$cmd' failed (Attempt $i/$attempts). Error: $output"
            [ $i -lt $attempts ] && sleep 5
        fi
    done
    return 1
}

log "Starting EC2 setup script"

# Install Docker
if ! command -v docker &> /dev/null; then
    log "Installing Docker..."
    if ! retry sudo amazon-linux-extras install docker -y; then
        log "Failed to install Docker. Exiting."
        exit 1
    fi
    sudo systemctl enable --now docker || { log "Failed to enable and start Docker."; exit 1; }
    sudo usermod -a -G docker ec2-user || { log "Failed to add ec2-user to docker group."; exit 1; }
else
    log "Docker is already installed. Ensuring Docker service is enabled and started..."
    sudo systemctl enable --now docker || { log "Failed to enable and start Docker."; exit 1; }
fi

# Install AWS CLI v2
sudo rm -rf /usr/local/aws-cli/ /usr/local/bin/aws /usr/local/bin/aws_completer /bin/aws || true
sudo yum remove awscli -y

log "Installing AWS CLI v2..."
if ! retry curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; then
    log "Failed to download AWS CLI v2. Exiting."
    exit 1
fi
unzip awscliv2.zip || { log "Failed to unzip AWS CLI package."; exit 1; }
sudo ./aws/install --bin-dir /bin || { log "Failed to install AWS CLI."; exit 1; }

# Cleanup
log "Cleaning up..."
rm -rf awscliv2.zip aws || log "Warning: Cleanup of AWS CLI installation files failed."

# Install Kubectl
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
EOF

sudo yum install -y kubectl || { log "Failed to install Kubectl."; exit 1; }

# Create and run Terraform Cloud Agent start script
log "Setting up Terraform Cloud Agent..."
cat << 'EOF' > /var/lib/cloud/scripts/per-boot/tfc-agent-start.sh
#!/bin/bash

# Stop and remove existing container if it exists
sudo docker stop terraform-agent 2>/dev/null || true
sudo docker rm terraform-agent 2>/dev/null || true

# Run the Terraform Cloud Agent container
sudo docker run -d \
    --name=terraform-agent \
    --restart=unless-stopped \
    -e TFC_AGENT_TOKEN=${tfc_agent_token} \
    -e TFC_AGENT_NAME=terraform-agent \
    hashicorp/tfc-agent:latest || { log "Failed to start Terraform Cloud Agent container."; exit 1; }

# Wait for container to be running
log "Waiting for Terraform Cloud Agent container to start..."
until sudo docker ps --filter "name=terraform-agent" --filter "status=running" --format "{{.Names}}"; do
    log "Waiting for container to start..."
    sleep 3
done
log "Terraform Cloud Agent container is running"

# Install AWS CLI and ArgoCD CLI in container
log "Installing AWS CLI and ArgoCD CLI in container..."
sudo docker exec -u root terraform-agent sh -c "
    # Install AWS CLI
    apt-get update && \
    apt-get install -y unzip curl && \
    curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip && \
    unzip awscliv2.zip && \
    ./aws/install && \
    aws --version || { echo 'Failed to install AWS CLI'; exit 1; } && \

    # Install ArgoCD CLI
    VERSION=\$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION) && \
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v\$VERSION/argocd-linux-amd64 && \
    install -m 555 argocd-linux-amd64 /usr/local/bin/argocd && \
    argocd version --client || { echo 'Failed to install ArgoCD CLI'; exit 1; } && \

    # Install Kubectl
    curl -LO "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl" && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin/kubectl && \
    kubectl version --client || { echo 'Failed to install Kubectl'; exit 1; } && \

    # Cleanup
    rm -rf aws awscliv2.zip argocd-linux-amd64" || { log "Failed to install tools in container"; exit 1; }

log "Terraform Cloud Agent setup completed successfully"
EOF

chmod +x /var/lib/cloud/scripts/per-boot/tfc-agent-start.sh || { log "Failed to make tfc-agent-start.sh executable."; exit 1; }
/var/lib/cloud/scripts/per-boot/tfc-agent-start.sh

log "EC2 setup script completed"