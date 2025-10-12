#!/bin/bash

set -e
set -x

# vimrc no mouse
cat <<EOF > /home/vyos/.vimrc
set mouse=
EOF

cat <<EOF > /root/.vimrc
set mouse=
EOF

# Fix permissions on /var/log/vyatta to prevent "can't initialize output" errors
# VyOS CLI needs to write configuration logs to this directory
mkdir -p /var/log/vyatta
chown -R root:vyattacfg /var/log/vyatta
chmod -R 775 /var/log/vyatta

