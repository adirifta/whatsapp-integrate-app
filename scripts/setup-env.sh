#!/bin/bash

# Environment Setup Script for cPanel
set -e

echo "🔧 Setting up cPanel environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Check if we're on cPanel server
if [ ! -d "/usr/local/cpanel" ]; then
    warn "This script is intended for cPanel servers. Some features may not work."
fi

# Setup Frontend Subdomain
setup_frontend() {
    log "Setting up frontend subdomain: fe.yourdomain.com"
    
    # Create subdomain directory
    mkdir -p ~/public_html/fe.yourdomain.com
    
    # Create .htaccess for SPA routing
    cat > ~/public_html/fe.yourdomain.com/.htaccess << 'EOF'
RewriteEngine On

# Redirect to HTTPS
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# SPA Fallback Routing
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.html [L]
EOF

    log "✅ Frontend subdomain setup completed"
}

# Setup Backend Subdomain
setup_backend() {
    log "Setting up backend subdomain: be.yourdomain.com"
    
    # Create subdomain directory
    mkdir -p ~/public_html/be.yourdomain.com
    
    # Install Node.js version if not exists
    if ! command -v node &> /dev/null; then
        log "Installing Node.js..."
        # Using Node Version Manager (nvm)
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install 18
        nvm use 18
    fi
    
    # Install PM2 for process management
    if ! command -v pm2 &> /dev/null; then
        log "Installing PM2..."
        npm install -g pm2
    fi
    
    # Create PM2 ecosystem file
    cat > ~/ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'whatsapp-backend',
    script: '~/public_html/be.yourdomain.com/server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3001
    },
    error_file: '~/logs/err.log',
    out_file: '~/logs/out.log',
    log_file: '~/logs/combined.log',
    time: true
  }]
};
EOF

    log "✅ Backend subdomain setup completed"
}

# Setup MySQL Database
setup_database() {
    log "Setting up MySQL database..."
    
    # You'll need to run these commands manually in cPanel MySQL interface
    cat > database_setup.sql << 'EOF'
-- Run these commands in cPanel MySQL Database interface
CREATE DATABASE whatsapp_dashboard;
USE whatsapp_dashboard;

CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin', 'user') DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE whatsapp_messages (
    id INT PRIMARY KEY AUTO_INCREMENT,
    message_id VARCHAR(255) UNIQUE,
    from_number VARCHAR(20) NOT NULL,
    to_number VARCHAR(20) NOT NULL,
    message TEXT,
    message_type ENUM('text', 'image', 'video', 'document', 'audio'),
    timestamp DATETIME,
    status ENUM('sent', 'delivered', 'read', 'error'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE whatsapp_contacts (
    id INT PRIMARY KEY AUTO_INCREMENT,
    contact_id VARCHAR(255) UNIQUE,
    name VARCHAR(255),
    number VARCHAR(20) NOT NULL,
    is_business BOOLEAN DEFAULT FALSE,
    last_seen DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

    log "📋 Database setup SQL created in database_setup.sql"
    log "💡 Please run these commands manually in cPanel MySQL interface"
}

# Main setup
main() {
    log "Starting cPanel environment setup..."
    
    setup_frontend
    setup_backend
    setup_database
    
    log "🎉 Environment setup completed!"
    log "📝 Next steps:"
    log "   1. Create subdomains in cPanel: fe.yourdomain.com and be.yourdomain.com"
    log "   2. Run database_setup.sql in cPanel MySQL interface"
    log "   3. Deploy your code using the deployment scripts"
    log "   4. Start the backend with: pm2 start ecosystem.config.js"
}

main "$@"