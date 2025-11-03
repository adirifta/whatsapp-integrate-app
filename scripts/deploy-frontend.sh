#!/bin/bash

# Deployment script for Frontend to cPanel via FTP
set -e

echo "🚀 Starting Frontend Deployment..."

# Configuration
ENVIRONMENT=${1:-staging}
FTP_SERVER=${FTP_SERVER}
FTP_USERNAME=${FTP_USERNAME}
FTP_PASSWORD=${FTP_PASSWORD}
FTP_PORT=${FTP_PORT:-21}
FRONTEND_DIR=${FRONTEND_DIR:-public_html}
API_URL=${API_URL:-http://localhost:5000/api}

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
    
    # Install dependencies
    log "Installing dependencies..."
    npm ci
    
    # Create environment file
    log "Creating environment configuration..."
    cat > .env.production << EOF
NEXT_PUBLIC_API_URL=$API_URL
NODE_ENV=production
EOF

    # Build the application
    log "Building Next.js application..."
    npm run build
    
    # Export static files (if using static export)
    log "Exporting static files..."
    npm run export || warn "Static export not configured, using build folder"
    
    cd ..
    log "Frontend build completed"
}

# Create backup of current deployment
create_backup() {
    local backup_dir="/tmp/frontend_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    log "Creating backup of current frontend deployment..."
    
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        mirror --reverse --verbose $FRONTEND_DIR $backup_dir;
        bye
    " || warn "Backup creation failed or no previous deployment found"
    
    log "Backup created at: $backup_dir"
}

# Deploy frontend via FTP
deploy_frontend() {
    log "Starting FTP deployment to $FTP_SERVER:$FRONTEND_DIR"
    
    # Determine build output directory
    local build_dir="frontend/out"
    if [ ! -d "$build_dir" ]; then
        build_dir="frontend/.next"
        if [ ! -d "$build_dir" ]; then
            build_dir="frontend/build"
        fi
    fi
    
    if [ ! -d "$build_dir" ]; then
        error "No build directory found. Please build the frontend first."
    fi
    
    log "Using build directory: $build_dir"
    
    # Create deployment package
    local temp_dir="/tmp/frontend_deploy_$(date +%s)"
    mkdir -p "$temp_dir"
    
    if [ -d "frontend/out" ]; then
        # Static export
        cp -r frontend/out/* "$temp_dir/"
    elif [ -d "frontend/.next" ]; then
        # Next.js build
        cp -r frontend/.next "$temp_dir/"
        cp -r frontend/public "$temp_dir/" 2>/dev/null || true
        cp frontend/package.json "$temp_dir/" 2>/dev/null || true
        cp frontend/next.config.js "$temp_dir/" 2>/dev/null || true
        
        # Create .htaccess for Next.js
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
EOF
    fi
    
    # Deploy using lftp
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        set cmd:fail-exit true;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        
        echo 'Creating directory structure...';
        mkdir -p $FRONTEND_DIR;
        cd $FRONTEND_DIR;
        
        echo 'Uploading files...';
        mirror --reverse --verbose --delete --parallel=10 $temp_dir .;
        
        echo 'Setting permissions...';
        chmod 755 .;
        chmod 644 index.html;
        chmod 644 .htaccess;
        find . -name '*.js' -exec chmod 644 {} \;
        find . -name '*.css' -exec chmod 644 {} \;
        find . -name '*.html' -exec chmod 644 {} \;
        
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
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://$FTP_SERVER/" > /dev/null 2>&1; then
            log "✅ Frontend health check passed!"
            return 0
        else
            warn "Health check attempt $attempt/$max_attempts failed, retrying..."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    error "Frontend health check failed after $max_attempts attempts"
}

# Create robots.txt and sitemap
create_seo_files() {
    log "Creating SEO files..."
    
    local temp_seo_dir="/tmp/seo_files_$(date +%s)"
    mkdir -p "$temp_seo_dir"
    
    # robots.txt
    cat > "$temp_seo_dir/robots.txt" << EOF
User-agent: *
Allow: /
Disallow: /api/
Disallow: /admin/

Sitemap: https://$FTP_SERVER/sitemap.xml
EOF

    # sitemap.xml
    cat > "$temp_seo_dir/sitemap.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>https://$FTP_SERVER/</loc>
        <lastmod>$(date +%Y-%m-%d)</lastmod>
        <changefreq>weekly</changefreq>
        <priority>1.0</priority>
    </url>
    <url>
        <loc>https://$FTP_SERVER/dashboard</loc>
        <lastmod>$(date +%Y-%m-%d)</lastmod>
        <changefreq>daily</changefreq>
        <priority>0.8</priority>
    </url>
</urlset>
EOF

    # Upload SEO files
    lftp -e "
        set ftp:ssl-allow no;
        set ssl:verify-certificate no;
        open -u $FTP_USERNAME,$FTP_PASSWORD $FTP_SERVER:$FTP_PORT;
        cd $FRONTEND_DIR;
        put $temp_seo_dir/robots.txt;
        put $temp_seo_dir/sitemap.xml;
        bye
    "
    
    rm -rf "$temp_seo_dir"
    log "SEO files created and uploaded"
}

# Main deployment function
main() {
    log "Starting frontend deployment for $ENVIRONMENT environment"
    
    validate_variables
    install_lftp
    # create_backup
    # build_frontend
    deploy_frontend
    create_seo_files
    health_check
    
    log "🎉 Frontend deployment completed successfully!"
}

# Run main function
main "$@"