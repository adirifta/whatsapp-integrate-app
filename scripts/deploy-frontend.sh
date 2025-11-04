#!/bin/bash

# Fixed deployment script for Frontend to cPanel via FTP
set -e

echo "🚀 Starting Frontend Deployment"

# Configuration
ENVIRONMENT=${1:-production}
FTP_SERVER=${FTP_SERVER}
FTP_USERNAME=${FTP_USERNAME}
FTP_PASSWORD=${FTP_PASSWORD}
FTP_PORT=${FTP_PORT:-21}
FRONTEND_DIR=${FRONTEND_DIR:-public_html}
API_URL=${API_URL}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Validate environment variables
validate_variables() {
    local required_vars=("FTP_SERVER" "FTP_USERNAME" "FTP_PASSWORD" "FRONTEND_DIR")
    
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

# Build frontend
build_frontend() {
    log "Building frontend for $ENVIRONMENT environment..."
    
    cd frontend
    
    # Clean up any existing builds
    rm -rf .next out build
    
    # Install dependencies
    log "Installing dependencies..."
    npm ci
    
    # Create environment file if API_URL is provided
    if [ -n "$API_URL" ]; then
        log "Setting API URL: $API_URL"
        cat > .env.production << EOF
NEXT_PUBLIC_API_URL=$API_URL
NODE_ENV=production
EOF
    else
        warn "API_URL not set, using default configuration"
    fi

    # Build the application
    log "Building Next.js application..."
    npm run build
    
    # Check if we should export static files
    if grep -q '"export"' package.json || [ -d ".next/static" ]; then
        log "Next.js build completed successfully"
    else
        error "Next.js build failed or no output generated"
    fi
    
    cd ..
    log "Frontend build completed"
}

# Deploy frontend via FTP
deploy_frontend() {
    log "Starting FTP deployment to $FTP_SERVER:$FRONTEND_DIR"
    
    # Determine build output directory
    local build_dir="frontend/.next"
    if [ ! -d "$build_dir" ]; then
        error "No build directory found. Please build the frontend first."
    fi
    
    log "Using build directory: $build_dir"
    
    # Create deployment package
    local temp_dir="/tmp/frontend_deploy_$(date +%s)"
    mkdir -p "$temp_dir"
    
    # Copy necessary files for Next.js deployment
    log "Preparing deployment package..."
    
    # Copy .next directory
    cp -r frontend/.next "$temp_dir/"
    
    # Copy public directory if it exists
    if [ -d "frontend/public" ]; then
        cp -r frontend/public "$temp_dir/"
    fi
    
    # Copy essential configuration files
    if [ -f "frontend/package.json" ]; then
        cp frontend/package.json "$temp_dir/"
    fi
    
    if [ -f "frontend/next.config.js" ]; then
        cp frontend/next.config.js "$temp_dir/"
    fi
    
    # Create .htaccess for proper routing
    cat > "$temp_dir/.htaccess" << 'EOF'
RewriteEngine On

# Handle client-side routing
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.html [L]

# Security headers
<IfModule mod_headers.c>
    Header set X-Content-Type-Options nosniff
    Header set X-Frame-Options DENY
    Header set X-XSS-Protection "1; mode=block"
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
</IfModule>

# Compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
</IfModule>

# Cache control
<FilesMatch "\.(html|htm)$">
    Header set Cache-Control "no-cache, no-store, must-revalidate"
</FilesMatch>

<FilesMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2)$">
    Header set Cache-Control "max-age=31536000, public"
</FilesMatch>
EOF

    log "Deployment package created with $(find "$temp_dir" -type f | wc -l) files"
    
    # Deploy using lftp with SIMPLE approach
    log "Uploading files via FTP..."
    
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        set cmd:fail-exit true;
        set ftp:list-options -a;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        
        echo 'Changing to target directory: $FRONTEND_DIR';
        cd $FRONTEND_DIR || mkdir -p $FRONTEND_DIR;
        cd $FRONTEND_DIR;
        
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
        
        echo 'Setting safe permissions...';
        chmod 755 .;
        
        echo 'Listing deployed files:';
        ls -la;
        
        echo 'Frontend deployment completed successfully!';
        bye
    "
    
    # Cleanup
    rm -rf "$temp_dir"
    log "Frontend deployment completed"
}

# Health check after deployment
health_check() {
    log "Performing frontend health check..."
    
    # Wait for files to be served
    sleep 10
    
    local max_attempts=10
    local attempt=1
    
    # Extract domain from FTP server (remove ftp. prefix if present)
    local domain="${FTP_SERVER#ftp.}"
    local health_url="http://$domain/"
    
    log "Testing frontend endpoint: $health_url"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s --connect-timeout 10 "$health_url" > /dev/null 2>&1; then
            log "✅ Frontend health check passed!"
            return 0
        else
            warn "Health check attempt $attempt/$max_attempts failed, retrying..."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    warn "Frontend health check failed after $max_attempts attempts"
    return 1
}

# Main deployment function
main() {
    log "Starting frontend deployment for $ENVIRONMENT environment"
    
    validate_variables
    install_lftp
    build_frontend
    deploy_frontend
    health_check
    
    log "🎉 Frontend deployment completed successfully!"
}

# Run main function
main "$@"