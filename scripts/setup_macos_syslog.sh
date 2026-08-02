#!/bin/bash
# Script to configure macOS syslog to forward to Docker Compose syslog-ng
# Usage: ./setup_syslog.sh

# Install syslog (if not already installed)
# Note: macOS syslog is built-in and doesn't need installation via brew
# For custom syslog tools, you can install via:
# brew install syslog-ng

echo "Setting up macOS syslog to forward to Docker Compose syslog-ng..."

# Create syslog configuration to forward to Docker Compose syslog-ng (running on localhost port 514)
cat > /tmp/mac-syslog.conf << 'EOF'
# Forward logs to Docker Compose syslog-ng container
*.info;mail.none;authpriv.none;cron.none    @localhost:514

# Allow remote logging
*.info;mail.none;authpriv.none;cron.none    @localhost:514
EOF

# Apply the configuration to the system (Write to main syslog config)
sudo cp /tmp/mac-syslog.conf /etc/syslog.conf

# Also add it to the active configuration path
sudo cp /tmp/mac-syslog.conf /etc/syslog.conf

echo "macOS syslog configuration updated to forward to localhost:514"

# Restart syslog service to apply changes
echo "Restarting syslog service..."
sudo launchctl unload /System/Library/LaunchDaemons/com.apple.syslogd.plist 2>/dev/null || true
sudo launchctl load /System/Library/LaunchDaemons/com.apple.syslogd.plist 2>/dev/null || true

echo "✅ macOS syslog configured to forward to Docker Compose syslog-ng"
echo "   Logs will now be sent to: localhost:514"