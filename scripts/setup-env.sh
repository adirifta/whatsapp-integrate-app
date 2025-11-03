#!/bin/bash

# Environment setup script
set -e

echo "🔧 Setting up deployment environment..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Check required tools
check_tools() {
    local tools=("node" "npm" "lftp" "curl")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            warn "$tool is not installed"
        else
            log "$tool is installed"
        fi
    done
}

# Setup Node.js if not installed
setup_node() {
    if ! command -v node &> /dev/null; then
        log "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
}

# Setup project dependencies
setup_dependencies() {
    log "Setting up project dependencies..."
    
    # Backend dependencies
    if [ -d "backend" ]; then
        cd backend
        npm ci
        cd ..
    fi
    
    # Frontend dependencies
    if [ -d "frontend" ]; then
        cd frontend
        npm ci
        cd ..
    fi
}

# Create configuration templates
create_config_templates() {
    log "Creating configuration templates..."
    
    # Backend .env template
    cat > backend/.env.template << 'EOF'
NODE_ENV=production
PORT=5000
DB_HOST=localhost
DB_USER=your_username
DB_PASSWORD=your_password
DB_NAME=whatsapp_dashboard
JWT_SECRET=your_jwt_secret_here
EOF

    # Frontend .env.template
    cat > frontend/.env.template << 'EOF'
NEXT_PUBLIC_API_URL=http://localhost:5000/api
NODE_ENV=production
EOF

    log "Configuration templates created"
}

# Setup Git hooks
setup_git_hooks() {
    log "Setting up Git hooks..."
    
    # Pre-push hook
    cat > .git/hooks/pre-push << 'EOF'
#!/bin/bash
echo "Running tests before push..."
npm test --prefix backend
npm test --prefix frontend
EOF
    
    chmod +x .git/hooks/pre-push
    log "Git hooks configured"
}

# Main setup function
main() {
    log "Starting environment setup..."
    
    check_tools
    setup_node
    setup_dependencies
    create_config_templates
    setup_git_hooks
    
    log "🎉 Environment setup completed!"
    log "Next steps:"
    log "1. Configure your .env files in backend/ and frontend/"
    log "2. Set up GitHub Secrets for deployment"
    log "3. Push to main/master branch to trigger deployment"
}

# Run main function
main "$@"