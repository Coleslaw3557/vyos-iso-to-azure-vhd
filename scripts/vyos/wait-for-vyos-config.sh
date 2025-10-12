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
