#!/bin/bash

set -e
set -x

# export DEBIAN_FRONTEND=noninteractive

# delete interfaces ethernet eth0 address
# delete interfaces ethernet eth0 hw-id
# delete system name-server

cat <<'EOF' > /home/vyos/configure-vyos.sh
#!/bin/vbash
# Check if we need to run with vyattacfg group
if [ $(id -gn) != vyattacfg ]; then
  exec sg vyattacfg "$0 $*"
fi

source /opt/vyatta/etc/functions/script-template
configure
set system host-name 'vyoshost'
commit
save
exit
EOF
chmod 0755 /home/vyos/configure-vyos.sh
chown vyos:vyattacfg /home/vyos/configure-vyos.sh
su - vyos -c "/home/vyos/configure-vyos.sh"
rm -rf /home/vyos/configure-vyos.sh
