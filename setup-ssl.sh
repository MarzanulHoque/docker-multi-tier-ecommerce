#!/bin/bash
# ==============================================================================
# AWS EC2 Production Setup & Automated HTTPS (Let's Encrypt SSL) Provisioner
# ==============================================================================

set -e

DOMAIN_NAME="$1"
EMAIL="$2"

if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL" ]; then
    echo "❌ Usage: ./setup-ssl.sh <your-domain.com> <your-email@example.com>"
    echo "Example: ./setup-ssl.sh shop.mydomain.com admin@mydomain.com"
    exit 1
fi

echo "🔒 Provisioning free Let's Encrypt HTTPS SSL Certificate for $DOMAIN_NAME..."

# 1. Create temporary self-signed certificate if Let's Encrypt certs don't exist yet
# (Required so Nginx can start up on Port 443 before Certbot runs)
mkdir -p ./ssl-dummy
if [ ! -d "/var/lib/docker/volumes/$(basename $PWD)_certbot_etc/_data/live/$DOMAIN_NAME" ]; then
    echo "🔑 Creating dummy certificate for Nginx initial boot..."
    docker run --rm -v $(pwd)/nginx/ssl:/etc/ssl alpine sh -c \
      "apk add --no-upgrade openssl && openssl req -x509 -nodes -newkey rsa:2048 -days 1 -keyout /etc/ssl/privkey.pem -out /etc/ssl/fullchain.pem -subj '/CN=localhost'"
fi

# 2. Issue real Let's Encrypt Certificate
echo "📜 Requesting official Let's Encrypt SSL Certificate..."
docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot \
    --email "$EMAIL" --agree-tos --no-eff-email \
    -d "$DOMAIN_NAME"

# 3. Reload Nginx to activate real SSL
echo "🔄 Reloading Nginx with new HTTPS SSL Certificate..."
docker compose exec proxy nginx -s reload

echo "=============================================================================="
echo "🎉 HTTPS Setup Complete! Your app is now live securely at: https://$DOMAIN_NAME"
echo "=============================================================================="
