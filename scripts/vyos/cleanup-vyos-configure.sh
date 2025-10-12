#!/bin/bash

set -e
set -x

export DEBIAN_FRONTEND=noninteractive

# delete interfaces ethernet eth0 address
# delete interfaces ethernet eth0 hw-id
# delete system name-server

cat <<EOF > /home/vyos/cleanup-vyos.sh
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure
set system host-name 'vyosbuild'
commit
save
exit
EOF
chmod 0700 /home/vyos/cleanup-vyos.sh
chown vyos:users /home/vyos/cleanup-vyos.sh
su - vyos -c "/home/vyos/cleanup-vyos.sh"

# run cleanup on vyos configure using python vyos.configtree, since can't remove interfaces via configure cli
config_update_url="http://${PACKER_HTTP_ADDR}/cleanup-vyos-configure.py"
wget --timeout=30 --tries=3 --retry-connrefused $config_update_url -O /home/vyos/cleanup-vyos-configure.py
chown vyos:users /home/vyos/cleanup-vyos-configure.py
chmod 0664 /home/vyos/cleanup-vyos-configure.py
python3 /home/vyos/cleanup-vyos-configure.py
rm -rf /home/vyos/cleanup-vyos-configure.py
