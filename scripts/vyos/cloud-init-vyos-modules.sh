#!/bin/bash
#
# Configure cloud-init modules for VyOS
# This script enables only the modules that are compatible with VyOS
#

set -e
set -x

# Only run if cloud-init is being used
if [[ "${CLOUD_INIT}" != "debian" && "${CLOUD_INIT}" != "vyos" ]]; then
    echo "$0 - info: cloud-init not enabled, skipping module configuration"
    exit 0
fi

echo "Configuring cloud-init modules for VyOS..."

# Create the main cloud.cfg for VyOS
cat <<'EOF' > /etc/cloud/cloud.cfg
# VyOS cloud-init configuration
# Only enable modules that are compatible with VyOS

# The modules that run in the 'init' stage
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - write_files
 - growpart
 - resizefs
 - disk_setup
 - mounts
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - ca_certs
 - rsyslog
 - users_groups
 - ssh

# The modules that run in the 'config' stage
cloud_config_modules:
 - ssh_import_id
 - locale
 - set_passwords
 - grub_dpkg
 - apt_pipelining
 - apt_configure
 - ubuntu_advantage
 - ntp
 - timezone
 - disable_ec2_metadata
 - runcmd
 - byobu

# The modules that run in the 'final' stage
cloud_final_modules:
 - package_update_upgrade_install
 - fan
 - landscape
 - lxd
 - ubuntu_drivers
 - write_files_deferred
 - puppet
 - chef
 - mcollective
 - salt_minion
 - reset_rmc
 - refresh_rmc_and_interface
 - rightscale_userdata
 - scripts_vendor
 - scripts_per_once
 - scripts_per_boot
 - scripts_per_instance
 - scripts_user
 - ssh_authkey_fingerprints
 - keys_to_console
 - install_hotplug
 - phone_home
 - final_message
 - power_state_change

# System and/or distro specific settings
# (not accessible to handlers/transforms)
system_info:
   distro: debian
   default_user:
     name: vyos
     lock_passwd: true
     gecos: VyOS User
     groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
     sudo: ["ALL=(ALL) NOPASSWD:ALL"]
     shell: /bin/bash
   paths:
      cloud_dir: /var/lib/cloud/
      templates_dir: /etc/cloud/templates/
      upstart_dir: /etc/init/
   package_mirrors:
     - arches: [i386, amd64]
       failsafe:
         primary: http://deb.debian.org/debian
         security: http://security.debian.org/
       search:
         primary:
           - http://%(ec2_region)s.ec2.archive.ubuntu.com/ubuntu/
           - http://%(availability_zone)s.clouds.archive.ubuntu.com/ubuntu/
           - http://%(region)s.clouds.archive.ubuntu.com/ubuntu/
         security: []
   ssh_svcname: ssh
EOF

# Create VyOS-specific cloud-init module configuration
cat <<'EOF' > /etc/cloud/cloud.cfg.d/10-vyos-modules.cfg
# VyOS cloud-init modules configuration
# Enable only write_files and vyos_userdata modules

# Disable most cloud-init modules except the ones VyOS needs
cloud_init_modules:
 - migrator
 - seed_random
 - write_files

cloud_config_modules:
 - write_files
 - vyos_userdata

cloud_final_modules:
 - scripts_user
 - final_message

# Register VyOS custom module
# Note: The vyos_userdata module should be provided by VyOS packages
EOF

# Create VyOS userdata handler if it doesn't exist
# This is a basic implementation - the actual one should come from VyOS packages
if [ ! -f /etc/cloud/cloud.cfg.d/vyos_userdata.py ]; then
    cat <<'EOF' > /usr/lib/python3/dist-packages/cloudinit/config/cc_vyos_userdata.py
"""
VyOS User Data Module for cloud-init

This module processes VyOS configuration commands from user-data.
"""

import os
import subprocess
from cloudinit import log as logging
from cloudinit import util
from cloudinit.settings import PER_INSTANCE

LOG = logging.getLogger(__name__)

frequency = PER_INSTANCE

def handle(name, cfg, cloud, log, args):
    """
    Process VyOS configuration commands from cloud-config user-data
    """
    if 'vyos_config_commands' not in cfg:
        LOG.debug("No VyOS configuration commands found")
        return

    commands = cfg.get('vyos_config_commands', [])
    if not commands:
        LOG.debug("Empty VyOS configuration commands list")
        return

    LOG.info("Processing %d VyOS configuration commands", len(commands))

    # Write commands to a temporary file
    config_file = '/tmp/cloud-init-vyos-config.txt'
    with open(config_file, 'w') as f:
        for cmd in commands:
            f.write(cmd + '\n')

    # Execute VyOS configuration commands
    try:
        # Source VyOS environment and run commands
        vyos_cmd = """
        source /opt/vyatta/etc/functions/script-template
        configure
        while read cmd; do
            eval "$cmd"
        done < {config_file}
        commit
        save
        exit
        """.format(config_file=config_file)

        result = subprocess.run(['/bin/vbash', '-c', vyos_cmd],
                                capture_output=True,
                                text=True,
                                check=True)
        
        LOG.info("VyOS configuration applied successfully")
        if result.stdout:
            LOG.debug("Command output: %s", result.stdout)
    
    except subprocess.CalledProcessError as e:
        LOG.error("Failed to apply VyOS configuration: %s", e)
        if e.stderr:
            LOG.error("Error output: %s", e.stderr)
        raise
    
    finally:
        # Clean up temporary file
        if os.path.exists(config_file):
            os.remove(config_file)
EOF
fi

echo "VyOS cloud-init modules configured successfully"