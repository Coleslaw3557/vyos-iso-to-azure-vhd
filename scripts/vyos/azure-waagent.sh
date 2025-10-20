#!/bin/bash
#
# Azure Linux Agent (waagent) installation for VyOS
#
# This script installs waagent with a minimal, VyOS-compatible configuration that:
# - Disables ALL provisioning functions to prevent conflicts with VyOS config system
# - Keeps only essential Azure functionality (extensions, monitoring, updates)
# - Ensures waagent starts AFTER VyOS services to avoid configuration conflicts
# - Prevents waagent from managing resources that VyOS controls (network, SSH, disks)

set -e
set -x

export DEBIAN_FRONTEND=noninteractive

# Use provided WAAGENT_VERSION or default to 2.14.0.1
WAAGENT_VERSION="${WAAGENT_VERSION:-2.14.0.1}"

echo "Installing Azure Linux Agent (waagent) v${WAAGENT_VERSION} from source..."
echo "Configuration: cloud-init handles provisioning, waagent handles extensions"

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
# Ensure waagent starts AFTER VyOS config system loads
Wants=network-online.target vyos-router.service
After=network-online.target vyos-router.service vyos-config.service
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

# Configure waagent to work with cloud-init
echo "Configuring waagent to work with cloud-init (extensions only mode)"

cat <<EOF > /etc/waagent.conf
# Microsoft Azure Linux Agent Configuration (v${WAAGENT_VERSION})
# Configured for extensions only - cloud-init handles provisioning

# CRITICAL: Always use cloud-init for provisioning
Provisioning.Agent=cloud-init
Provisioning.DeleteRootPassword=n
Provisioning.RegenerateSshHostKeyPair=n
Provisioning.MonitorHostName=n
Provisioning.DecodeCustomData=n
Provisioning.ExecuteCustomData=n

# Keep extensions for Azure functionality
Extensions.Enabled=y
Extensions.GoalStatePeriod=6

# Disable resource disk management - VyOS handles its own disks
ResourceDisk.Format=n
ResourceDisk.EnableSwap=n

# Logging - keep minimal
Logs.Verbose=n
Logs.Collect=y
Logs.CollectPeriod=3600

# Network settings - let VyOS handle networking
OS.EnableFirewall=n
OS.MonitorDhcpClientRestartPeriod=0
OS.RemovePersistentNetRulesPeriod=0
OS.AllowHTTP=n

# Keep SCSI timeout for Azure storage
OS.RootDeviceScsiTimeout=300
OS.RootDeviceScsiTimeoutPeriod=30

# SSH - VyOS manages this
OS.SshClientAliveInterval=0
OS.SshDir=/etc/ssh

# Auto-update agent for security patches
AutoUpdate.UpdateToLatestVersion=y
AutoUpdate.Enabled=y

# Resource limits
CGroups.EnforceLimits=y
CGroups.Excluded=customscript,runcommand

# Protocol discovery
Protocol.EndpointDiscovery=static

# HTTP proxy settings (if needed)
HttpProxy.Host=None
HttpProxy.Port=None
EOF

# Enable waagent service
systemctl enable walinuxagent.service

echo "Azure Linux Agent v${WAAGENT_VERSION} installed and configured"
echo "Verifying waagent configuration..."
waagent --version
echo "Provisioning agent: $(grep -i "Provisioning.Agent" /etc/waagent.conf)"
echo "Auto-update: $(grep -i "AutoUpdate.UpdateToLatestVersion" /etc/waagent.conf)"
