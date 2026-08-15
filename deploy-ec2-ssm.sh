#!/bin/bash
# ==============================================================================
# AWS EC2 Production Deployment Script with AWS SSM / Secrets Manager Integration
# ==============================================================================

set -e

# Name of the parameter in AWS Systems Manager Parameter Store or Secrets Manager
SSM_PARAM_NAME="${1:-/prod/ecommerce/db_password}"

# Auto-detect AWS Region from EC2 Instance Metadata Service (IMDSv2 & v1 fallback)
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
    DETECTED_REGION=$(curl -s -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
else
    DETECTED_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
fi

AWS_REGION="${AWS_REGION:-${DETECTED_REGION:-us-east-1}}"

echo "🌍 Detected AWS Region: $AWS_REGION"
echo "🔐 Fetching database password securely from AWS SSM Parameter Store ($SSM_PARAM_NAME)..."

if command -v aws &> /dev/null; then
    # Retrieve secret securely into memory (never saved to disk)
    POSTGRES_PASSWORD=$(aws ssm get-parameter \
        --name "$SSM_PARAM_NAME" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region "$AWS_REGION")
        
    if [ -z "$POSTGRES_PASSWORD" ]; then
        echo "❌ Error: Could not retrieve secret from AWS SSM."
        exit 1
    fi
    echo "✅ Secret successfully retrieved from AWS SSM into memory."
else
    echo "⚠️ AWS CLI not installed. Falling back to environment variable or manual prompt."
    if [ -z "$POSTGRES_PASSWORD" ]; then
        read -sp "Enter PostgreSQL Password: " POSTGRES_PASSWORD
        echo ""
    fi
fi

# Export to current session and launch Docker Compose
export POSTGRES_PASSWORD

echo "🚀 Launching Docker Multi-Tier Application Stack..."
docker compose up --build -d

echo "=============================================================================="
echo "🎉 Deployment successful! Containers running with secure AWS SSM credentials."
echo "=============================================================================="
