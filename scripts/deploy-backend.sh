#!/bin/bash

# Deployment script for Backend to cPanel via FTP
set -e

echo "🚀 Starting Backend Deployment..."

# Configuration
ENVIRONMENT=${1:-staging}
FTP_SERVER=${FTP_SERVER}
FTP_USERNAME=${FTP_USERNAME}
FTP_PASSWORD=${FTP_PASSWORD}
FTP_PORT=${FTP_PORT:-21}
BACKEND_DIR=${BACKEND_DIR:-backend}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Validate environment variables
validate_variables() {
    local required_vars=("FTP_SERVER" "FTP_USERNAME" "FTP_PASSWORD")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required environment variable $var is not set"
        fi
    done
    
    log "Environment variables validated"
}

# Install lftp if not available
install_lftp() {
    if ! command -v lftp &> /dev/null; then
        log "Installing lftp..."
        sudo apt-get update && sudo apt-get install -y lftp
    fi
}

# Test FTP connection
test_ftp_connection() {
    log "Testing FTP connection to $FTP_SERVER..."
    
    if lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        ls;
        bye
    " > /dev/null 2>&1; then
        log "FTP connection successful"
    else
        error "FTP connection failed"
    fi
}

# Prepare backend for deployment
prepare_backend() {
    log "Preparing backend for deployment..."
    
    cd backend
    
    # Clean up any existing node_modules
    rm -rf node_modules
    
    # Install dependencies
    log "Installing dependencies..."
    npm ci --only=production
    
    # Remove development files
    rm -rf node_modules/.cache
    rm -rf tests .github .git .DS_Store
    
    # Remove test files if they exist
    find . -name "*.test.js" -delete 2>/dev/null || true
    find . -name "*.spec.js" -delete 2>/dev/null || true
    
    cd ..
    log "Backend preparation completed"
}

# Deploy backend via FTP
deploy_backend() {
    log "Starting FTP deployment to $FTP_SERVER:$BACKEND_DIR"
    
    # Create deployment package
    local temp_dir="/tmp/backend_deploy_$(date +%s)"
    mkdir -p "$temp_dir"
    
    # Copy backend files (excluding node_modules and other unnecessary files)
    log "Copying files to temporary directory..."
    cp -r backend/* "$temp_dir/" 2>/dev/null || true
    
    # Remove files that shouldn't be deployed
    rm -rf "$temp_dir/node_modules" "$temp_dir/.git" "$temp_dir/.github" 2>/dev/null || true
    rm -f "$temp_dir"/*.log 2>/dev/null || true
    
    log "Deployment package created with $(find "$temp_dir" -type f | wc -l) files"
    
    # Deploy using lftp with SIMPLE exclude patterns
    log "Uploading files via FTP..."
    
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        set cmd:fail-exit true;
        set ftp:list-options -a;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        
        echo 'Creating directory: $BACKEND_DIR';
        mkdir -p $BACKEND_DIR;
        cd $BACKEND_DIR;
        
        echo 'Starting file upload...';
        lcd $temp_dir;
        mirror --reverse \
               --verbose \
               --delete \
               --parallel=3 \
               --exclude node_modules/ \
               --exclude .git/ \
               --exclude .github/ \
               . .;
        
        echo 'Setting basic permissions...';
        chmod 755 .;
        
        echo 'Listing deployed files:';
        ls -la;
        
        echo 'Backend deployment completed successfully!';
        bye
    "
    
    # Cleanup
    rm -rf "$temp_dir"
    log "Backend deployment completed"
}

# Health check after deployment
health_check() {
    log "Performing health check..."
    
    # Wait for application to start
    sleep 10
    
    local max_attempts=10
    local attempt=1
    
    # Extract domain from FTP server (remove ftp. prefix if present)
    local domain="${FTP_SERVER#ftp.}"
    local health_url="http://$domain/$BACKEND_DIR/api/health"
    
    log "Testing health endpoint: $health_url"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s --connect-timeout 10 "$health_url" > /dev/null 2>&1; then
            log "✅ Backend health check passed!"
            return 0
        else
            warn "Health check attempt $attempt/$max_attempts failed, retrying..."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    warn "Health check failed after $max_attempts attempts"
    return 1
}

# Main deployment function
main() {
    log "Starting backend deployment for $ENVIRONMENT environment"
    
    validate_variables
    install_lftp
    test_ftp_connection
    prepare_backend
    deploy_backend
    health_check
    
    log "🎉 Backend deployment completed successfully!"
}

# Run main function
main "$@"