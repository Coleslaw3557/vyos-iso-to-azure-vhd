#!/bin/bash

set -e
set -x

export DEBIAN_FRONTEND=noninteractive

rm -rf /home/vyos/cleanup-vyos.sh

# fix config permissions since if we edited with root user
# sudo chown -R root:vyattacfg /opt/vyatta/config/active/

# Skip waagent deprovision to preserve Provisioning.Agent configuration
# The deprovision step resets waagent.conf to defaults (Provisioning.Agent=auto)
# Since this is a fresh Packer build, deprovision is not necessary
echo "Skipping waagent deprovision to preserve configuration..."

# reconfiguring ssh
rm -f /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# cleanup apt
rm -f /etc/apt/sources.list.d/debian.list
apt -y autoremove --purge
apt-get clean

# cleanup machine-id
truncate -s 0 /etc/machine-id

# removing /tmp files
rm -rf /tmp/*

# removing log files
rm -rf /var/log/*

# removing history
export HISTFILE=0
rm -f /home/vyos/.bash_history
rm -f /root/.bash_history

# removing disk data
dd if=/dev/zero of=/EMPTY bs=1M || :
rm -f /EMPTY
sync
