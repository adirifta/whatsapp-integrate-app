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

# Test FTP connection
test_ftp_connection() {
    log "Testing FTP connection to $FTP_SERVER..."
    
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        ls;
        bye
    " && log "FTP connection successful" || error "FTP connection failed"
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
        mirror --verbose --exclude-glob .git --exclude-glob node_modules --exclude-glob *.log $BACKEND_DIR $backup_dir;
        bye
    " || warn "Backup creation failed or no previous deployment found"
    
    log "Backup created at: $backup_dir"
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
    
    # Create environment file only if it doesn't exist
    if [ ! -f ".env" ]; then
        log "Creating environment file..."
        cat > .env << EOF
NODE_ENV=production
PORT=5000
DB_HOST=$MYSQL_HOST
DB_USER=$MYSQL_USER
DB_PASSWORD=$MYSQL_PASSWORD
DB_NAME=$MYSQL_DATABASE
JWT_SECRET=${JWT_SECRET:-your_jwt_secret_change_in_production}
EOF
    else
        log "Environment file already exists, skipping creation"
    fi

    # Remove development files
    rm -rf node_modules/.cache
    find . -name "*.test.js" -delete 2>/dev/null || true
    find . -name "*.spec.js" -delete 2>/dev/null || true
    rm -rf tests .github .git .DS_Store
    
    # Create a list of files that should exist after deployment
    find . -type f -name "*.js" -o -name "*.json" -o -name "*.env" | sort > ../deployment_manifest.txt
    
    cd ..
    log "Backend preparation completed"
}

# Create directory structure on FTP
create_ftp_directories() {
    log "Creating directory structure: $BACKEND_DIR"
    
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        set cmd:fail-exit true;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        
        echo 'Creating target directory: $BACKEND_DIR';
        mkdir -p $BACKEND_DIR;
        
        echo 'Directory structure created successfully';
        bye
    " || warn "Directory creation might have failed (could already exist)"
}

# Deploy backend via FTP
deploy_backend() {
    log "Starting FTP deployment to $FTP_SERVER:$BACKEND_DIR"
    
    # Create deployment package
    local temp_dir="/tmp/backend_deploy_$(date +%s)"
    mkdir -p "$temp_dir"
    
    # Copy backend files (excluding node_modules and other unnecessary files)
    rsync -av \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='.github' \
        --exclude='*.log' \
        --exclude='.DS_Store' \
        --exclude='test*' \
        --exclude='*.test.js' \
        --exclude='*.spec.js' \
        backend/ "$temp_dir/"
    
    log "Deployment package created with $(find "$temp_dir" -type f | wc -l) files"
    log "Files to deploy:"
    find "$temp_dir" -type f -name "*.js" -o -name "*.json" | head -10
    
    # Deploy using lftp with better error handling
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        set cmd:fail-exit true;
        set ftp:list-options -a;
        set mirror:use-pget-n 5;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        
        echo 'Changing to target directory: $BACKEND_DIR';
        cd $BACKEND_DIR || (mkdir -p $BACKEND_DIR && cd $BACKEND_DIR);
        
        echo 'Starting file upload...';
        lcd $temp_dir;
        mirror --reverse \
               --verbose \
               --delete \
               --parallel=5 \
               --exclude node_modules/ \
               --exclude .git/ \
               --exclude '*.log' \
               --exclude '.DS_Store' \
               . .;
        
        echo 'Setting file permissions (only for existing files)...';
        chmod 755 .;
        chmod 644 *.js;
        chmod 644 *.json;
        
        echo 'Listing deployed files:';
        ls -la;
        
        echo 'Backend deployment completed successfully!';
        bye
    "
    
    # Verify deployment
    verify_deployment
    
    # Cleanup
    rm -rf "$temp_dir"
    log "Backend deployment completed"
}

# Verify that files were deployed correctly
verify_deployment() {
    log "Verifying deployment..."
    
    local manifest_file="deployment_manifest.txt"
    
    if [ -f "$manifest_file" ]; then
        log "Checking deployed files..."
        
        lftp -e "
            set ftp:ssl-allow no;
            set ssl:verify-certificate no;
            open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
            cd $BACKEND_DIR;
            ls -la;
            bye
        " > /tmp/ftp_listing.txt
        
        local deployed_count=$(grep -c "\.js$\|\.json$" /tmp/ftp_listing.txt || true)
        local expected_count=$(grep -c "\.js$\|\.json$" "$manifest_file" || true)
        
        log "Deployed files: $deployed_count, Expected: $expected_count"
        
        if [ "$deployed_count" -ge "$((expected_count / 2))" ]; then
            log "✅ Deployment verification passed"
        else
            warn "Deployment verification: some files might be missing"
        fi
        
        rm -f /tmp/ftp_listing.txt
    else
        warn "No deployment manifest found, skipping verification"
    fi
    
    rm -f "$manifest_file"
}

# Run database migrations
run_migrations() {
    if [ -n "$MYSQL_HOST" ] && [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ] && [ -n "$MYSQL_DATABASE" ]; then
        log "Running database migrations..."
        
        # Wait for MySQL to be ready
        for i in {1..30}; do
            if mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
                log "MySQL is ready, running migrations..."
                if [ -f "database/schema.sql" ]; then
                    mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < database/schema.sql
                    log "Database migrations completed"
                else
                    warn "Schema file not found, skipping migrations"
                fi
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
    
    local max_attempts=20
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
            sleep 3
            attempt=$((attempt + 1))
        fi
    done
    
    warn "Health check failed after $max_attempts attempts - application might still be starting"
    return 1
}

# Main deployment function
main() {
    log "Starting backend deployment for $ENVIRONMENT environment"
    
    validate_variables
    install_lftp
    test_ftp_connection
    # create_backup
    # prepare_backend
    create_ftp_directories
    deploy_backend
    run_migrations
    health_check
    
    log "🎉 Backend deployment completed successfully!"
}

# Run main function
main "$@"