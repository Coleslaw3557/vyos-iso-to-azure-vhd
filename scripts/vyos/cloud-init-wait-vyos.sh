#!/bin/bash

set -e
set -x

echo "Configuring cloud-init to wait for VyOS router service..."

# Install the VyOS configuration wait script
WAIT_SCRIPT="/usr/local/bin/wait-for-vyos-config.sh"
cat <<'SCRIPT_EOF' > "${WAIT_SCRIPT}"
#!/bin/bash
#
# Wait for VyOS configuration to complete before allowing cloud-init to proceed
#
# This script polls for the VyOS configuration completion marker file.
# VyOS creates /tmp/vyos-config-status with value "0" when configuration succeeds.
#
# Exit codes:
#   0 - VyOS configuration completed successfully
#   1 - Timeout waiting for configuration (60 seconds)
#

TIMEOUT=60
MARKER_FILE="/tmp/vyos-config-status"

echo "Waiting for VyOS configuration to complete..."

for i in $(seq 1 $TIMEOUT); do
    if [ -f "$MARKER_FILE" ] && [ "$(cat "$MARKER_FILE" 2>/dev/null)" = "0" ]; then
        echo "VyOS configuration completed successfully after $i seconds"
        exit 0
    fi
    sleep 1
done

echo "ERROR: Timeout waiting for VyOS configuration after $TIMEOUT seconds"
echo "Marker file status:"
if [ -f "$MARKER_FILE" ]; then
    echo "  File exists with content: $(cat "$MARKER_FILE" 2>/dev/null)"
else
    echo "  File does not exist"
fi
exit 1
SCRIPT_EOF

chmod +x "${WAIT_SCRIPT}"
echo "Installed VyOS configuration wait script to ${WAIT_SCRIPT}"

# Create systemd drop-in directory for cloud-final.service
DROPIN_DIR="/etc/systemd/system/cloud-final.service.d"
mkdir -p "${DROPIN_DIR}"

# Create drop-in configuration to ensure cloud-init waits for VyOS
# This prevents cloud-init user scripts from running before VyOS config system is ready
cat <<EOF > "${DROPIN_DIR}/wait-for-vyos.conf"
[Unit]
# Ensure cloud-init waits for VyOS router service to be ready
# This prevents race condition where user scripts run before VyOS can apply config
After=vyos-router.service
Wants=vyos-router.service

[Service]
# Wait for VyOS configuration to actually complete (polls /tmp/vyos-config-status)
# This replaces the fixed sleep with active polling for configuration completion
ExecStartPre=${WAIT_SCRIPT}
EOF

# Reload systemd to pick up the new configuration
systemctl daemon-reload

echo "Cloud-init systemd ordering configured successfully"
echo "cloud-final.service will now wait for vyos-router.service and poll for configuration completion"
