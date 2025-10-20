#!/bin/bash

set -e
set -x

if [[ "${CLOUD_INIT}" == "debian" ||  "${CLOUD_INIT}" == "vyos" ]]; then
    if [[ "${CLOUD_INIT_DATASOURCE}" == "nocloud_configdrive" ]]; then
        cat <<EOF > /etc/cloud/cloud.cfg.d/99-datasource.cfg
datasource_list: [ NoCloud, ConfigDrive ]
EOF
    elif [[ "${CLOUD_INIT_DATASOURCE}" == "azure" ]]; then
        cat <<EOF > /etc/cloud/cloud.cfg.d/99-datasource.cfg
datasource_list: [ Azure ]
datasource:
  Azure:
    apply_network_config: false
    agent_command: [/usr/sbin/waagent, -start]
EOF
    elif [[ "${CLOUD_INIT_DATASOURCE}" == "azure_fallback" ]]; then
        # Azure with NoCloud/ConfigDrive fallback for testing
        cat <<EOF > /etc/cloud/cloud.cfg.d/99-datasource.cfg
datasource_list: [ Azure, NoCloud, ConfigDrive ]
datasource:
  Azure:
    apply_network_config: false
    agent_command: [/usr/sbin/waagent, -start]
EOF
    else
        echo "$0 - info: cloud_init_datasource will not run, not supported cloud_init_datasource"
        exit 0
    fi
else
    echo "$0 - info: cloud_init_datasource will not run, not supported cloud_init"
fi
