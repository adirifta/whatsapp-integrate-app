#!/bin/bash

# Backend Deployment Script
set -e

echo "🚀 Starting Backend Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
BE_DIR="backend"
FTP_SERVER=$1
FTP_USER=$2
FTP_PASS=$3
REMOTE_DIR="./public_html/be.yourdomain.com/"
SSH_HOST=$4
SSH_USER=$5

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if required parameters are provided
if [ -z "$FTP_SERVER" ] || [ -z "$FTP_USER" ] || [ -z "$FTP_PASS" ]; then
    error "Missing FTP credentials. Usage: ./deploy-be.sh <ftp_server> <ftp_user> <ftp_pass> [ssh_host] [ssh_user]"
fi

# Check if backend directory exists
if [ ! -d "$BE_DIR" ]; then
    error "Backend directory not found: $BE_DIR"
fi

# Prepare backend for production
log "Preparing backend for production..."
cd $BE_DIR

# Install production dependencies
log "Installing production dependencies..."
npm ci --production

# Create production environment file
if [ -f ".env" ]; then
    warn "Backing up existing .env file"
    cp .env .env.backup
fi

log "Creating production environment configuration..."
cat > .env << EOF
NODE_ENV=production
PORT=${{ secrets.BE_PORT }}
DB_HOST=${{ secrets.DB_HOST }}
DB_USER=${{ secrets.DB_USER }}
DB_PASSWORD=${{ secrets.DB_PASSWORD }}
DB_NAME=${{ secrets.DB_NAME }}
JWT_SECRET=${{ secrets.JWT_SECRET }}
EOF

# Create cPanel configuration files
log "Creating cPanel configuration files..."

# .htaccess for Apache
cat > .htaccess << 'EOF'
RewriteEngine On

# Redirect to HTTPS
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# Proxy to Node.js application
RewriteRule ^$ http://127.0.0.1:${{ secrets.BE_PORT }}/ [P,L]
RewriteRule ^(.*)$ http://127.0.0.1:${{ secrets.BE_PORT }}/$1 [P,L]
EOF

cd ..

# Deploy via FTP
log "Deploying backend to FTP server..."
lftp -e "
set ftp:ssl-allow no;
open -u $FTP_USER,$FTP_PASS $FTP_SERVER;
cd $REMOTE_DIR;
mirror -R --delete --verbose $BE_DIR/ .;
quit"

# Restart application via SSH if credentials provided
if [ ! -z "$SSH_HOST" ] && [ ! -z "$SSH_USER" ]; then
    log "Restarting application via SSH..."
    ssh $SSH_USER@$SSH_HOST << 'EOF'
        cd ~/public_html/be.yourdomain.com
        npm install --production
        # Check if PM2 is installed and restart app
        if command -v pm2 &> /dev/null; then
            pm2 restart whatsapp-backend || pm2 start server.js --name whatsapp-backend
        else
            # Fallback: kill existing process and start new one
            pkill -f "node server.js" || true
            nohup node server.js > app.log 2>&1 &
        fi
EOF
else
    warn "SSH credentials not provided. Manual restart required on server."
fi

log "✅ Backend deployment completed successfully!"