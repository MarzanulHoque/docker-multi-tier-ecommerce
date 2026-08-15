#!/bin/bash
# ==============================================================================
# AWS EC2 Production Setup & Deployment Script
# Tested on: Ubuntu 24.04 LTS / Ubuntu 22.04 LTS / Amazon Linux 2023
# ==============================================================================

set -e

echo "🚀 Starting EC2 Setup for Docker Multi-Tier App..."

# 1. Update system packages
echo "📦 Updating package index..."
if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg git awscli
elif command -v dnf &> /dev/null; then
    sudo dnf update -y
    sudo dnf install -y curl git awscli
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

# 4. Auto-detect AWS Region from EC2 Metadata (IMDSv2)
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
    DETECTED_REGION=$(curl -s -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
fi
AWS_REGION="${AWS_REGION:-${DETECTED_REGION:-us-east-1}}"

# 5. Fetch Database Password from AWS SSM Parameter Store into Memory
echo "🌍 Detected AWS Region: $AWS_REGION"
echo "🔐 Fetching database password from AWS SSM Parameter Store (/prod/ecommerce/db_password)..."

if command -v aws &> /dev/null; then
    POSTGRES_PASSWORD=$(aws ssm get-parameter \
        --name "/prod/ecommerce/db_password" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "⚠️ Could not retrieve secret from AWS SSM automatically."
    read -sp "Enter PostgreSQL Password manually: " POSTGRES_PASSWORD
    echo ""
fi

# 6. Launch Application Stack with Docker Compose
export POSTGRES_PASSWORD

echo "🚀 Building and launching Docker Compose multi-tier stack..."
sudo -E docker compose up --build -d

echo "=============================================================================="
echo "🎉 EC2 Deployment Complete!"
echo "=============================================================================="
echo "Your multi-tier application is now running live!"
echo "Ensure EC2 Security Group inbound rules allow traffic on Port 80 (HTTP)."
echo "=============================================================================="