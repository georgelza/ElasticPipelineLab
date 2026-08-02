#!/bin/bash
# Script to configure macOS Filebeat to forward to Docker Compose Kafka cluster
# Usage: ./setup_filebeat.sh

# Install Filebeat via Homebrew if not already installed
# brew install filebeat

echo "Setting up macOS Filebeat to forward to Docker Compose Kafka..."

# Create Filebeat configuration for macOS
cat > /tmp/filebeat.yml << 'EOF'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/*.log
  fields:
    source: macos

output.kafka:
  hosts: ["localhost:9092"]
  topic: "filebeat-logs"
  compression: gzip
  max_message_bytes: 1000000

# Required to have Kafka connector 
processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
EOF

# Install Filebeat via Homebrew if not already installed (macOS)
if ! command -v filebeat &> /dev/null; then
    echo "Installing Filebeat via Homebrew..."
    brew install filebeat
fi

# Copy config to the proper location
sudo mkdir -p /etc/filebeat
sudo cp /tmp/filebeat.yml /etc/filebeat/filebeat.yml

echo "macOS Filebeat configuration updated to forward to Kafka at localhost:9092"

# Load and start Filebeat service  
echo "Starting Filebeat service..."
sudo brew services start filebeat

echo "✅ macOS Filebeat configured to forward to Docker Compose Kafka"
echo "   Logs will now be sent to: localhost:9092 (Kafka broker)"