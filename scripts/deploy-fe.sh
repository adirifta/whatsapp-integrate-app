#!/bin/bash

# Frontend Deployment Script
set -e

echo "🚀 Starting Frontend Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
FE_DIR="frontend"
BUILD_DIR="frontend/out"
FTP_SERVER=$1
FTP_USER=$2
FTP_PASS=$3
REMOTE_DIR="./public_html/fe.yourdomain.com/"

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
    error "Missing FTP credentials. Usage: ./deploy-fe.sh <ftp_server> <ftp_user> <ftp_pass>"
fi

# Check if frontend directory exists
if [ ! -d "$FE_DIR" ]; then
    error "Frontend directory not found: $FE_DIR"
fi

# Build frontend
log "Building frontend..."
cd $FE_DIR

# Install dependencies
log "Installing dependencies..."
npm ci

# Build project
log "Building project..."
npm run build
npm run export

# Verify build
if [ ! -d "$BUILD_DIR" ]; then
    error "Build directory not found: $BUILD_DIR"
fi

# Deploy via FTP
log "Deploying to FTP server..."
lftp -e "
set ftp:ssl-allow no;
open -u $FTP_USER,$FTP_PASS $FTP_SERVER;
cd $REMOTE_DIR;
mirror -R --delete --verbose $BUILD_DIR/ .;
quit"

log "✅ Frontend deployment completed successfully!"

# Cleanup
log "Cleaning up..."
cd ..
rm -rf $BUILD_DIR

log "🎉 Frontend deployment finished!"