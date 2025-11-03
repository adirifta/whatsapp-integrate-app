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
BACKEND_DIR=${BACKEND_DIR:-public_html/backend}
MYSQL_HOST=${MYSQL_HOST}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}

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
    local required_vars=("FTP_SERVER" "FTP_USERNAME" "FTP_PASSWORD" "BACKEND_DIR")
    
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

# Create backup of current deployment
create_backup() {
    local backup_dir="/tmp/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    log "Creating backup of current deployment..."
    
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        mirror --reverse --verbose $BACKEND_DIR $backup_dir;
        bye
    " || warn "Backup creation failed or no previous deployment found"
    
    log "Backup created at: $backup_dir"
}

# Prepare backend for deployment
prepare_backend() {
    log "Preparing backend for deployment..."
    
    cd backend
    
    # Install dependencies
    log "Installing dependencies..."
    npm ci --only=production
    
    # Create environment file
    log "Creating environment file..."
    cat > .env << EOF
NODE_ENV=production
PORT=5000
DB_HOST=$MYSQL_HOST
DB_USER=$MYSQL_USER
DB_PASSWORD=$MYSQL_PASSWORD
DB_NAME=$MYSQL_DATABASE
JWT_SECRET=$JWT_SECRET
EOF

    # Remove development files
    rm -rf node_modules/.cache
    find . -name "*.test.js" -delete
    find . -name "*.spec.js" -delete
    
    cd ..
    log "Backend preparation completed"
}

# Deploy backend via FTP
deploy_backend() {
    log "Starting FTP deployment to $FTP_SERVER:$BACKEND_DIR"
    
    # Create deployment package
    local temp_dir="/tmp/backend_deploy_$(date +%s)"
    mkdir -p "$temp_dir"
    cp -r backend/* "$temp_dir/"
    
    # Remove files that shouldn't be deployed
    rm -f "$temp_dir/.env.local"
    rm -rf "$temp_dir/tests"
    rm -rf "$temp_dir/.github"
    
    # Deploy using lftp
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        set cmd:fail-exit true;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        
        echo 'Creating directory structure...';
        mkdir -p $BACKEND_DIR;
        cd $BACKEND_DIR;
        
        echo 'Uploading files...';
        mirror --reverse --verbose --delete --parallel=10 $temp_dir .;
        
        echo 'Setting permissions...';
        chmod 755 .;
        chmod 644 package.json;
        chmod 644 server.js;
        chmod 644 .env;
        
        echo 'Deployment completed successfully!';
        bye
    "
    
    # Cleanup
    rm -rf "$temp_dir"
    log "Backend deployment completed"
}

# Run database migrations
run_migrations() {
    if [ -n "$MYSQL_HOST" ] && [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ] && [ -n "$MYSQL_DATABASE" ]; then
        log "Running database migrations..."
        
        # Wait for MySQL to be ready
        for i in {1..30}; do
            if mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
                log "MySQL is ready, running migrations..."
                mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < database/schema.sql
                log "Database migrations completed"
                return 0
            else
                warn "MySQL not ready yet, waiting... (attempt $i/30)"
                sleep 2
            fi
        done
        warn "MySQL not available, skipping migrations"
    else
        warn "MySQL credentials not provided, skipping migrations"
    fi
}

# Health check after deployment
health_check() {
    log "Performing health check..."
    
    # Wait for application to start
    sleep 10
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://$FTP_SERVER/$BACKEND_DIR/../api/health" > /dev/null 2>&1; then
            log "✅ Backend health check passed!"
            return 0
        else
            warn "Health check attempt $attempt/$max_attempts failed, retrying..."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    error "Health check failed after $max_attempts attempts"
}

# Main deployment function
main() {
    log "Starting backend deployment for $ENVIRONMENT environment"
    
    validate_variables
    install_lftp
    create_backup
    prepare_backend
    deploy_backend
    run_migrations
    health_check
    
    log "🎉 Backend deployment completed successfully!"
}

# Run main function
main "$@"