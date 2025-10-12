import json
from vyos.configtree import ConfigTree

config_path = '/config/config.boot'

with open(config_path, 'r') as file:
    config_string = file.read()

config = ConfigTree(config_string=config_string)

interfaces = config.list_nodes(['interfaces', 'ethernet'])

# Keep eth0 for first boot connectivity, but remove hw-id to avoid MAC binding issues
# Delete any additional interfaces (eth1, eth2, etc.)
for interface in interfaces:
    if interface == 'eth0':
        # Remove hw-id from eth0 to prevent MAC address binding issues
        hw_id_path = ['interfaces', 'ethernet', interface, 'hw-id']
        if config.exists(hw_id_path):
            config.delete(hw_id_path)
    else:
        # Remove all other interfaces (eth1, eth2, etc.)
        interface_path = ['interfaces', 'ethernet', interface]
        config.delete(interface_path)

with open(config_path, 'w') as config_file:
    config_file.write(config.to_string())
