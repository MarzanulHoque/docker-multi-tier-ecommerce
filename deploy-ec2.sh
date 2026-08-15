#!/bin/bash
# ==============================================================================
# AWS EC2 Production Deployment Script
# Fast, idempotent deployment (Skips package installation if Docker is present)
# ==============================================================================

set -e

echo "🚀 Starting EC2 Production Deployment..."

# 1. Install prerequisites ONCE only if Docker is missing
if ! command -v docker &> /dev/null; then
    echo "📦 Initializing host dependencies & installing Docker Engine..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y
        sudo apt-get install -y ca-certificates curl gnupg git || true
    fi

    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh

    sudo usermod -aG docker $USER
    sudo systemctl enable docker
    sudo systemctl start docker
    echo "✅ Docker installed successfully!"
else
    echo "⚡ Docker is already installed. Skipping package installation."
fi

# 2. Auto-detect AWS Region from EC2 Metadata (IMDSv2)
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
    DETECTED_REGION=$(curl -s -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
fi
AWS_REGION="${AWS_REGION:-${DETECTED_REGION:-us-east-1}}"

# 3. Fetch Database Password from AWS SSM Parameter Store into Memory
echo "🌍 Detected AWS Region: $AWS_REGION"
echo "🔐 Fetching database password from AWS SSM Parameter Store..."
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
    if [ -t 0 ]; then
        read -sp "Enter PostgreSQL Password manually: " POSTGRES_PASSWORD
        echo ""
    else
        echo "⚡ Non-interactive shell detected. Generating dynamic container password."
        POSTGRES_PASSWORD=$(openssl rand -hex 16)
    fi
fi

# 4. Fast Rebuild & Redeploy using Docker Cache
export POSTGRES_PASSWORD

echo "🏗️ Building & updating containers..."
sudo -E docker compose up --build -d

echo "=============================================================================="
echo "⚡ Deployment complete! Containers running:"
sudo docker compose ps
echo "=============================================================================="