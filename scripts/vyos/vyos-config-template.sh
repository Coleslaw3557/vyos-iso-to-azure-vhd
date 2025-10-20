#!/bin/vbash
# VyOS Configuration Script Template
# This script ensures proper execution with vyattacfg group permissions

# Check if we need to run with vyattacfg group
if [ $(id -gn) != vyattacfg ]; then
  exec sg vyattacfg "$0 $*"
fi

# Source the VyOS functions
source /opt/vyatta/etc/functions/script-template

# Enter configuration mode
configure

# Example configuration commands (replace with actual config)
# set system host-name 'vyoshost'
# set interfaces ethernet eth0 address dhcp
# set service ssh port 22

# Commit and save changes
commit
save

# Exit configuration mode
exit