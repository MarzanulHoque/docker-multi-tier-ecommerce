#!/bin/bash
# ==============================================================================
# AWS EC2 User Data (Bootstrap Script for Instance Creation)
# Paste this into "User Data" under Advanced Details when creating EC2 instance.
# Tested on: Ubuntu 24.04 LTS
# ==============================================================================

set -e

# Log all output to /var/log/user-data.log for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "🚀 Starting Automated EC2 Launch Bootstrapping..."

# 1. Update system packages & install prerequisites
apt-get update -y
apt-get install -y ca-certificates curl gnupg git awscli

# 2. Install Docker Engine & Docker Compose Plugin
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

usermod -aG docker ubuntu || true
systemctl enable docker
systemctl start docker

# 3. Clone Repository
APP_DIR="/home/ubuntu/docker-multi-tier-ecommerce"
if [ ! -d "$APP_DIR" ]; then
    echo "📦 Cloning application repository..."
    git clone https://github.com/MarzanulHoque/docker-multi-tier-ecommerce.git "$APP_DIR"
    chown -R ubuntu:ubuntu "$APP_DIR"
fi

cd "$APP_DIR"

# 4. Auto-detect AWS Region via IMDSv2
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
    DETECTED_REGION=$(curl -s -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
fi
AWS_REGION="${DETECTED_REGION:-us-east-1}"

# 5. Fetch Password from AWS SSM Parameter Store into Memory
echo "🔐 Fetching database password from AWS SSM Parameter Store..."
POSTGRES_PASSWORD=$(aws ssm get-parameter \
    --name "/prod/ecommerce/db_password" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "FallbackPassword2026!")

# 6. Launch Application Stack via Docker Compose
export POSTGRES_PASSWORD
echo "🚀 Building and launching Docker Compose multi-tier stack..."
docker compose up --build -d

echo "=============================================================================="
echo "🎉 EC2 Automated User Data Bootstrapping Finished Successfully!"
echo "=============================================================================="
