#!/bin/bash

set -e
set -x

# Get VyOS version
VYOS_VERSION=$(cat /opt/vyatta/etc/version 2>/dev/null || echo "")
echo "Detected VyOS version: $VYOS_VERSION"

# Check if this is the affected version
if [[ "$VYOS_VERSION" == *"1.5-stream-2025"* ]]; then
    echo "Fixing VyOS 1.5-stream-2025-Q2 critical bugs..."

    # Fix 1: Bash function names cannot contain hyphens
    echo "Fixing bash function syntax errors..."

    # Fix vyatta-cfg-run
    if [ -f /opt/vyatta/share/vyatta-cfg/functions/interpreter/vyatta-cfg-run ]; then
        sed -i 's/vyatta_config_commit-confirm/vyatta_config_commit_confirm/g' /opt/vyatta/share/vyatta-cfg/functions/interpreter/vyatta-cfg-run
        sed -i 's/vyatta_config_rollback-soft/vyatta_config_rollback_soft/g' /opt/vyatta/share/vyatta-cfg/functions/interpreter/vyatta-cfg-run
        sed -i 's/vyatta_rollback-soft_complete/vyatta_rollback_soft_complete/g' /opt/vyatta/share/vyatta-cfg/functions/interpreter/vyatta-cfg-run
        sed -i 's/rollback-soft/rollback_soft/g' /opt/vyatta/share/vyatta-cfg/functions/interpreter/vyatta-cfg-run
        echo "Fixed vyatta-cfg-run"
    fi

    # Fix script-template
    if [ -f /opt/vyatta/etc/functions/script-template ]; then
        sed -i 's/no-match/no_match/g' /opt/vyatta/etc/functions/script-template
        sed -i 's/no-more/no_more/g' /opt/vyatta/etc/functions/script-template
        echo "Fixed script-template"
    fi

    # Fix bash completion
    if [ -f /etc/bash_completion.d/vyatta-cfg ]; then
        sed -i 's/vyatta_rollback-soft_complete/vyatta_rollback_soft_complete/g' /etc/bash_completion.d/vyatta-cfg
        sed -i 's/commit-confirm/commit_confirm/g' /etc/bash_completion.d/vyatta-cfg
        echo "Fixed bash completion"
    fi

    echo "VyOS 1.5-stream-2025-Q2 bug fixes completed successfully"
else
    echo "This is not VyOS 1.5-stream-2025-Q2, skipping version-specific bug fixes"
fi