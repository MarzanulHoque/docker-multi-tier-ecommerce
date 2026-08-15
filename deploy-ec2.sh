#!/bin/bash
# ==============================================================================
# AWS EC2 Production Setup & Deployment Script
# Multi-stage Docker build & launch
# Tested on: Ubuntu 24.04 LTS / Ubuntu 22.04 LTS
# ==============================================================================

set -e

echo "🚀 Starting EC2 Production Deployment..."

# 1. Update system packages & install prerequisites
echo "📦 Updating package index & installing dependencies..."
if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg git awscli
elif command -v dnf &> /dev/null; then
    sudo dnf update -y
    sudo dnf install -y curl git awscli
fi

# 2. Install Docker & Docker Compose if not present
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh

    sudo usermod -aG docker $USER
    echo "✅ Docker installed successfully!"
else
    echo "✅ Docker is already installed."
fi

# 3. Ensure Docker service is running
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

# 6. Execute Multi-Stage Build & Launch Stack via Docker Compose
export POSTGRES_PASSWORD

echo "🏗️ Building multi-stage Docker images & launching stack..."
sudo -E docker compose up --build -d

echo "=============================================================================="
echo "🎉 EC2 Production Multi-Stage Deployment Complete!"
echo "=============================================================================="
echo "Containers running:"
sudo docker compose ps
echo "=============================================================================="