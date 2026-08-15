#!/bin/bash
# ==============================================================================
# AWS EC2 Automated Setup Script for Docker Multi-Tier Application
# Tested on: Ubuntu 22.04 LTS / Ubuntu 24.04 LTS / Amazon Linux 2023
# ==============================================================================

set -e

echo "🚀 Starting EC2 Setup for Docker Multi-Tier App..."

# 1. Update system packages
echo "📦 Updating package index..."
if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg git
elif command -v dnf &> /dev/null; then
    sudo dnf update -y
    sudo dnf install -y curl git
fi

# 2. Install Docker & Docker Compose if not present
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh

    # Add current user to docker group to run docker without sudo
    sudo usermod -aG docker $USER
    echo "✅ Docker installed successfully!"
else
    echo "✅ Docker is already installed."
fi

# 3. Ensure Docker service is running & enabled
echo "⚙️ Enabling and starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

# 4. Verify Docker Compose plugin
if docker compose version &> /dev/null; then
    echo "✅ Docker Compose plugin available!"
else
    echo "📦 Installing Docker Compose plugin..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get install -y docker-compose-plugin
    fi
fi

# 5. Summary & Instructions
echo "=============================================================================="
echo "🎉 EC2 Docker Setup Complete!"
echo "=============================================================================="
echo "To deploy your stack on this EC2 instance:"
echo ""
echo "  1. Exit and re-login (or run: 'newgrp docker') so group permissions take effect."
echo "  2. Clone your repository or transfer files to this EC2 instance."
echo "  3. Run the application stack:"
echo "       docker compose up --build -d"
echo ""
echo "  4. Ensure EC2 Security Group inbound rules allow Traffic on Port 80 (HTTP)."
echo "=============================================================================="
