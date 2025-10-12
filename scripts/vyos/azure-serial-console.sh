#!/bin/bash

set -e
set -x

echo "Configuring Azure serial console (ttyS0)..."

# GRUB configuration files
GRUB_CFG="/boot/grub/grub.cfg"
GRUB_DEFAULT="/etc/default/grub"

# Backup original configs
cp ${GRUB_DEFAULT} ${GRUB_DEFAULT}.bak
cp ${GRUB_CFG} ${GRUB_CFG}.bak

# Configure GRUB to use serial terminal for bootloader menu
# Insert serial configuration commands after the initial preamble (after "set timeout=")
sed -i '/^set timeout=/a\
# Serial console configuration for Azure\
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1\
terminal_input serial console\
terminal_output serial console' ${GRUB_CFG}

# Add serial console parameters to kernel command line in grub.cfg
# This adds console=ttyS0,115200n8 console=tty0 to all kernel boot entries
sed -i 's/\(linux.*\) console=tty[0-9]*/\1 console=ttyS0,115200n8 console=tty0/' ${GRUB_CFG}

# Also add it if there's no existing console= parameter
sed -i '/^[[:space:]]*linux.*vmlinuz/s/\(.*\)/\1 console=ttyS0,115200n8 console=tty0/' ${GRUB_CFG}
# Remove duplicates that may have been created
sed -i 's/console=ttyS0,115200n8 console=tty0 console=ttyS0,115200n8 console=tty0/console=ttyS0,115200n8 console=tty0/' ${GRUB_CFG}

# Configure /etc/default/grub for future kernel updates
# Note: We can't run update-grub due to overlay filesystem, but this ensures
# future manual updates will preserve serial console settings
cat <<EOF >> ${GRUB_DEFAULT}

# Azure Serial Console Configuration
# Note: These settings are for reference; grub.cfg has been manually updated
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX_DEFAULT="\${GRUB_CMDLINE_LINUX_DEFAULT} console=ttyS0,115200n8 console=tty0"
EOF

# Enable getty on serial port for login prompt
systemctl enable serial-getty@ttyS0.service

echo "Azure serial console configured successfully"
echo "Serial console will be available at ttyS0 (115200 baud, 8N1)"
echo "GRUB has been configured to output to both serial and VGA consoles"
