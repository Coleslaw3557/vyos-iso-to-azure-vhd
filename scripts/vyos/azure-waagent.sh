#!/bin/bash

set -e
set -x

export DEBIAN_FRONTEND=noninteractive

# Determine the provisioning mode
# PROVISIONING_AGENT can be: 'waagent' (standalone) or 'cloud-init' (with optional waagent)
PROVISIONING_MODE="${PROVISIONING_AGENT:-waagent}"

# Use provided WAAGENT_VERSION or default to 2.14.0.1
WAAGENT_VERSION="${WAAGENT_VERSION:-2.14.0.1}"

echo "Installing Azure Linux Agent (waagent) v${WAAGENT_VERSION} from source..."
echo "Provisioning mode: ${PROVISIONING_MODE}"

# Install required dependencies for building from source
apt update -qq
apt install -y \
    python3 \
    python3-setuptools \
    python3-distutils \
    python-is-python3 \
    unzip \
    wget \
    openssl \
    iptables \
    sudo

# Download WALinuxAgent from GitHub
WAAGENT_URL="https://github.com/Azure/WALinuxAgent/archive/refs/tags/v${WAAGENT_VERSION}.zip"
WAAGENT_DIR="/tmp/walinuxagent"

echo "Downloading WALinuxAgent v${WAAGENT_VERSION}..."
mkdir -p "${WAAGENT_DIR}"
cd "${WAAGENT_DIR}"
wget -q "${WAAGENT_URL}" -O walinuxagent.zip

echo "Extracting WALinuxAgent..."
unzip -q walinuxagent.zip
cd "WALinuxAgent-${WAAGENT_VERSION}"

echo "Installing WALinuxAgent from source..."
python3 setup.py install

# Clean up
cd /
rm -rf "${WAAGENT_DIR}"

echo "WALinuxAgent v${WAAGENT_VERSION} installed successfully"

# Determine waagent binary location
WAAGENT_BIN=$(which waagent 2>/dev/null || echo "/usr/sbin/waagent")
echo "waagent binary location: ${WAAGENT_BIN}"

# Create symlink to /usr/sbin if installed elsewhere
if [ "${WAAGENT_BIN}" != "/usr/sbin/waagent" ] && [ -f "${WAAGENT_BIN}" ]; then
    ln -sf "${WAAGENT_BIN}" /usr/sbin/waagent
    WAAGENT_BIN="/usr/sbin/waagent"
fi

# Create systemd service file manually
echo "Creating walinuxagent systemd service..."
cat <<SERVICEEOF > /etc/systemd/system/walinuxagent.service
[Unit]
Description=Azure Linux Agent
Wants=network-online.target sshd.service sshd-keygen.service
After=network-online.target
ConditionFileIsExecutable=${WAAGENT_BIN}

[Service]
Type=simple
ExecStart=${WAAGENT_BIN} -daemon
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Reload systemd to pick up the new service
systemctl daemon-reload

# Configure waagent based on provisioning mode
if [[ "${PROVISIONING_MODE}" == "cloud-init" ]]; then
    PROVISIONING_AGENT_CONFIG="cloud-init"
    echo "Configuring waagent to work with cloud-init (cloud-init handles provisioning)"
else
    PROVISIONING_AGENT_CONFIG="waagent"
    echo "Configuring waagent as standalone provisioning agent"
fi

cat <<EOF > /etc/waagent.conf
# Microsoft Azure Linux Agent Configuration (v${WAAGENT_VERSION})

# Provisioning agent configuration
Provisioning.Agent=${PROVISIONING_AGENT_CONFIG}

# Monitor hostname changes
Provisioning.MonitorHostName=y

# Resource disk configuration (Azure temporary disk)
ResourceDisk.Format=y
ResourceDisk.Filesystem=ext4
ResourceDisk.MountPoint=/mnt/resource
ResourceDisk.EnableSwap=n

# Logging configuration
Logs.Verbose=n
Logs.Collect=y
Logs.CollectPeriod=3600

# HTTP proxy settings (if needed)
HttpProxy.Host=None
HttpProxy.Port=None

# Network and OS settings
OS.EnableRDMA=n
OS.RootDeviceScsiTimeout=300
OS.EnableFirewall=n
OS.MonitorDhcpClientRestartPeriod=30
OS.SshClientAliveInterval=180

# Enable VM extensions
Extensions.Enabled=y
Extensions.GoalStatePeriod=6

# Auto-update settings (UpdateToLatestVersion is recommended for v2.14+)
AutoUpdate.UpdateToLatestVersion=y
AutoUpdate.Enabled=y

# CGroups resource limits
CGroups.EnforceLimits=y
EOF

# Enable waagent service
systemctl enable walinuxagent.service

echo "Azure Linux Agent v${WAAGENT_VERSION} installed and configured"
echo "Verifying waagent configuration..."
waagent --version
echo "Provisioning agent: $(grep -i "Provisioning.Agent" /etc/waagent.conf)"
echo "Auto-update: $(grep -i "AutoUpdate.UpdateToLatestVersion" /etc/waagent.conf)"
