#!/bin/bash

set -e
set -x

echo "Fixing VyOS configuration permissions..."

# Fix ownership on active config directory
if [ -d /opt/vyatta/config/active/ ]; then
    echo "Restoring proper permissions on /opt/vyatta/config/active/"
    chown -R root:vyattacfg /opt/vyatta/config/active/
    chmod -R g+rwX /opt/vyatta/config/active/
fi

# Clean up stale config sessions
echo "Cleaning up stale config sessions..."

# Kill any stale unionfs processes
pkill -f 'unionfs-fuse.*config' || true

# Remove stale session directories
rm -rf /opt/vyatta/config/tmp/changes_only_* || true
rm -rf /opt/vyatta/config/tmp/new_config_* || true

# Ensure tmp directory has correct permissions
if [ -d /opt/vyatta/config/tmp ]; then
    chown root:vyattacfg /opt/vyatta/config/tmp
    chmod 775 /opt/vyatta/config/tmp
fi

# Fix permissions on other important config directories
for dir in /opt/vyatta/config /config; do
    if [ -d "$dir" ]; then
        echo "Fixing permissions on $dir"
        chown -R root:vyattacfg "$dir"
        find "$dir" -type d -exec chmod 775 {} \;
        find "$dir" -type f -exec chmod 664 {} \;
    fi
done

# Ensure vyos user is in vyattacfg group
if id -u vyos &>/dev/null; then
    echo "Ensuring vyos user is in vyattacfg group"
    usermod -a -G vyattacfg vyos || true
fi

echo "VyOS permission fixes completed successfully"