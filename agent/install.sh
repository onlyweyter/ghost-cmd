#!/bin/bash

# GHOST CMD - Agent Installer
# Run on each agent server

set -e

echo "🚀 GHOST CMD Agent Installer"
echo "============================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root: sudo bash install.sh"
    exit 1
fi

# ==========================================
# 1. Get Dashboard URL from user
# ==========================================
read -p "📊 Enter Dashboard URL (e.g., https://dashboard.jujulefek.qzz.io): " DASHBOARD_URL

if [ -z "$DASHBOARD_URL" ]; then
    echo "❌ Dashboard URL cannot be empty"
    exit 1
fi

# ==========================================
# 2. System Update
# ==========================================
echo "📦 Updating system packages..."
apt-get update && apt-get upgrade -y
apt-get install -y python3 python3-pip python3-venv git curl wget xvfb xvfb-run

# ==========================================
# 3. Install Chrome
# ==========================================
echo "🌐 Installing Google Chrome..."
if ! command -v google-chrome &> /dev/null; then
    wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
    sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
    apt-get update
    apt-get install -y google-chrome-stable
else
    echo "   ✅ Chrome already installed"
fi

# ==========================================
# 4. Setup Python Environment
# ==========================================
echo "🐍 Setting up Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt

# ==========================================
# 5. Create directories
# ==========================================
echo "📁 Creating directories..."
mkdir -p chrome_profiles
mkdir -p logs

# ==========================================
# 6. Setup Cloudflare Tunnel
# ==========================================
echo "🌐 Setting up Cloudflare Tunnel for Agent..."

if ! command -v cloudflared &> /dev/null; then
    echo "   Downloading cloudflared..."
    wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O cloudflared
    chmod +x cloudflared
    mv cloudflared /usr/local/bin/
fi

read -p "   Create new tunnel? (y/n): " CREATE_TUNNEL

if [ "$CREATE_TUNNEL" = "y" ]; then
    echo "   Authenticating with Cloudflare..."
    cloudflared tunnel login
    
    read -p "   Enter tunnel name (e.g., ghost-agent-01): " AGENT_TUNNEL_NAME
    
    AGENT_TUNNEL_ID=$(cloudflared tunnel create $AGENT_TUNNEL_NAME | grep -oP '(?<=\()[a-f0-9\-]+(?=\))' | head -1)
    
    read -p "   Enter public hostname (e.g., agent-01.yourdomain.com): " AGENT_HOSTNAME
    
    cat > agent-tunnel.yaml <<EOF
tunnel: $AGENT_TUNNEL_ID
credentials-file: ~/.cloudflare-warp/cert.pem

ingress:
  - hostname: $AGENT_HOSTNAME
    service: http://localhost:7860
  - service: http_status:404
EOF
    
    echo "   Tunnel created: $AGENT_TUNNEL_ID"
    echo "   Config saved to agent-tunnel.yaml"
else
    echo "   Skipping tunnel creation"
fi

# ==========================================
# 7. Create environment file
# ==========================================
echo "⚙️  Creating environment configuration..."

cat > .env <<EOF
DASHBOARD_URL=$DASHBOARD_URL
AUTH_KEY=GHOST_SECRET_2026
EOF

# ==========================================
# 8. Create Agent Service
# ==========================================
echo "⚙️  Creating agent systemd service..."

cat > /etc/systemd/system/ghost-agent.service <<EOF
[Unit]
Description=GHOST CMD Agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
EnvironmentFile=$(pwd)/.env
ExecStart=$(pwd)/venv/bin/python3 agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ghost-agent.service

# ==========================================
# 9. Create Tunnel Service (if created)
# ==========================================
if [ "$CREATE_TUNNEL" = "y" ]; then
    echo "🔗 Creating tunnel systemd service..."
    
    cat > /etc/systemd/system/ghost-agent-tunnel.service <<EOF
[Unit]
Description=GHOST CMD Agent Tunnel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=/usr/local/bin/cloudflared tunnel --config agent-tunnel.yaml run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ghost-agent-tunnel.service
fi

# ==========================================
# 10. Start Services
# ==========================================
echo "🚀 Starting services..."
systemctl start ghost-agent.service

if [ "$CREATE_TUNNEL" = "y" ]; then
    sleep 1
    systemctl start ghost-agent-tunnel.service
fi

sleep 2

echo ""
echo "✅ Installation Complete!"
echo "============================"
echo "📊 Dashboard URL: $DASHBOARD_URL"
echo "🚀 Agent Port: http://localhost:7860"
if [ "$CREATE_TUNNEL" = "y" ]; then
    echo "🌐 Public URL: https://$AGENT_HOSTNAME"
fi
echo ""
echo "🔧 Manage services:"
echo "   systemctl status ghost-agent"
if [ "$CREATE_TUNNEL" = "y" ]; then
    echo "   systemctl status ghost-agent-tunnel"
fi
echo "   systemctl restart ghost-agent"
echo ""
echo "📋 Logs:"
echo "   journalctl -u ghost-agent -f"
if [ "$CREATE_TUNNEL" = "y" ]; then
    echo "   journalctl -u ghost-agent-tunnel -f"
fi
echo ""
echo "Agent will now register to dashboard automatically..."
echo ""
