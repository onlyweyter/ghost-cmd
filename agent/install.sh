#!/bin/bash
# GHOST CMD - Agent Installer (Ubuntu 22.04 Fixed v2)
# Run on each agent server
set -e

echo "🚀 GHOST CMD Agent Installer"
echo "============================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root: sudo bash install-agent.sh"
    exit 1
fi

# ==========================================
# 1. Get Dashboard URL
# ==========================================
read -p "📊 Enter Dashboard URL (e.g., https://dashboard.jujulefek.qzz.io): " DASHBOARD_URL
if [ -z "$DASHBOARD_URL" ]; then
    echo "❌ Dashboard URL cannot be empty"
    exit 1
fi

# ==========================================
# 2. System Update & Dependencies (Clean 22.04)
# ==========================================
echo "📦 Updating system packages..."

apt-get update && apt-get upgrade -y

# Enable universe repository
apt-get install -y software-properties-common
add-apt-repository universe -y
apt-get update

echo "📦 Installing Chrome + XVFB dependencies..."
apt-get install -y \
    python3 python3-pip python3-venv git curl wget \
    xvfb x11-utils \
    libasound2t64 \
    libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libx11-6 libxcb1 libxcomposite1 libxdamage1 libxrandr2 libxtst6 \
    libnss3 libnspr4 \
    libgtk-3-0t64 libgbm1 libxshmfence1 \
    libdbus-1-3 \
    fonts-liberation ca-certificates libcups2 libdrm2

echo "✅ Dependencies installed successfully"

# ==========================================
# 3. Install Google Chrome
# ==========================================
echo "🌐 Installing Google Chrome..."
if ! command -v google-chrome &> /dev/null; then
    echo "📦 Adding Google Chrome repository..."
    wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    
    apt-get update
    apt-get install -y google-chrome-stable
    echo "✅ Google Chrome installed"
else
    echo "✅ Google Chrome already installed"
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
mkdir -p chrome_profiles logs

# ==========================================
# 6. Create .env file
# ==========================================
echo "⚙️ Creating .env configuration..."
cat > .env <<EOF
DASHBOARD_URL=$DASHBOARD_URL
AUTH_KEY=GHOST_SECRET_2026
EOF

# ==========================================
# 7. Create Systemd Service
# ==========================================
echo "⚙️ Creating ghost-agent systemd service..."

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
Environment=PYTHONUNBUFFERED=1
Environment=DISPLAY=:99
XDG_RUNTIME_DIR=/run/user/0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ghost-agent.service

# ==========================================
# 8. Start Service
# ==========================================
echo "🚀 Starting agent service..."
systemctl start ghost-agent.service

sleep 3

# ==========================================
# 9. Final Message
# ==========================================
echo ""
echo "✅ Agent Installation Complete! (Ubuntu 22.04)"
echo "============================"
echo "📊 Dashboard URL : $DASHBOARD_URL"
echo "🚀 Agent running on http://localhost:7860"
echo ""
echo "🔧 Service commands:"
echo "   systemctl status ghost-agent"
echo "   systemctl restart ghost-agent"
echo "   journalctl -u ghost-agent -f"
echo ""
echo "🎉 Selesai!"
echo ""

systemctl status ghost-agent --no-pager -l
