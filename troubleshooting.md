# VyOS Troubleshooting Guide

## Cloud-Init and Waagent Configuration

### Azure Configuration

This project uses cloud-init as the primary provisioning agent with waagent for Azure extensions:

- **Cloud-init**: Handles all provisioning tasks (SSH keys, user-data, initial configuration)
- **Waagent**: Configured with `Provisioning.Agent=cloud-init` to manage Azure extensions only
- **Azure datasource**: Configured with `apply_network_config: false` to let VyOS manage network
- **VyOS modules**: Cloud-init configured with only VyOS-compatible modules (write_files, vyos_userdata)

### Verifying the Configuration

**Check cloud-init status and configuration:**
```bash
# Check cloud-init status
cloud-init status --long

# Verify Azure datasource configuration
grep -A5 "Azure" /etc/cloud/cloud.cfg.d/91_azure_datasource.cfg
# Should show: apply_network_config: false

# Check VyOS modules configuration
cat /etc/cloud/cloud.cfg.d/92_vyos_modules.cfg
# Should show only: [write_files, vyos_userdata]
```

**Check waagent configuration:**
```bash
# Verify waagent provisioning mode
grep "Provisioning.Agent" /etc/waagent.conf
# Should show: Provisioning.Agent=cloud-init

# Check waagent service
sudo systemctl status walinuxagent

# Check waagent logs
sudo journalctl -u walinuxagent -n 100
sudo cat /var/log/waagent.log | tail -100
```

**Expected behavior:**
- Waagent should show it's deferring provisioning to cloud-init
- Look for: "Provisioning handler is cloud-init"
- Waagent should be managing extensions only

### Troubleshooting Provisioning Issues

**Verify waagent started by cloud-init:**

```bash
# Verify cloud-init started waagent
sudo cat /var/log/cloud-init.log | grep -i "waagent"
# Should show waagent being started by cloud-init via agent_command
```

**Common provisioning issues:**

1. **Wrong Provisioning.Agent setting**: Should always be `cloud-init`
2. **Waagent starting too early**: Cloud-init should start waagent via agent_command
3. **Image not deprovisioned**: Image must be generalized with `waagent -deprovision+user -force`
4. **Network config conflicts**: Azure datasource must have `apply_network_config: false`

## VyOS Cloud-Init Configure Mode Failure - Root Cause Analysis

## Symptom

When deploying a VyOS image to Azure with cloud-init configuration:
- VM boots successfully
- Can SSH in using default credentials (vyos/vyos)
- Running `configure` command fails with: **"Failed to set up config session"**
- VyOS configuration is empty (no interfaces, no firewall rules, no NAT)

## Root Cause

### The Race Condition

VyOS has a unique boot process where the configuration system initializes **after** most system services:

```
Timeline of VM Boot:
~23s: systemd starts services
~24s: vyos-router.service starts
~25s: cloud-init modules:final runs (executes user-data scripts)
~25s: cloud-init FINISHES
~27s: VyOS waits for NICs to settle
~32s: VyOS mounts config filesystem
~37s: VyOS applies configuration ("Configuration success")
```

**The Problem**: Cloud-init finishes at 25 seconds, but VyOS doesn't actually apply configuration until 37 seconds - a **12-second gap**.

### What Happens During Boot

1. **Cloud-init runs user vbash script** (at 25s)
2. Script sources VyOS functions: `source /opt/vyatta/etc/functions/script-template`
3. Script runs: `configure` command
4. **`configure` tries to set up config session** but VyOS config system isn't mounted yet
5. The `configure` command calls: `/opt/vyatta/sbin/my_cli_shell_api setupSession`
6. This creates a FUSE mount: `/opt/vyatta/config/tmp/new_config_1461`
7. **Session setup fails** because VyOS isn't ready
8. Script exits due to error (vbash uses `set -e`)
9. **FUSE mount is left orphaned/stuck**
10. VyOS finishes mounting and applying config (at 37s), but it's too late

### The Stuck Mount

After the failed cloud-init attempt, the system has:

```bash
$ mount | grep vyatta
unionfs-fuse on /opt/vyatta/config/tmp/new_config_1461 type fuse.unionfs-fuse (rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other)
```

This mount cannot be unmounted with normal commands:
- `umount` fails: "no mount point specified"
- `fusermount -u` fails: "not found in /etc/mtab"

### Why Future Configure Attempts Fail

The `configure` command workflow:

1. User runs: `configure`
2. Bash calls: `newgrp vyattacfg` (starts new shell with vyattacfg group)
3. New shell sources: `/etc/bash_completion.d/vyatta-cfg`
4. Completion script calls: `vyatta_cli_shell_api setupSession` (line 1062)
5. This calls: `/opt/vyatta/sbin/my_cli_shell_api setupSession`
6. **C++ binary crashes** with exception:

```
terminate called after throwing an instance of 'std::out_of_range'
  what():  basic_string::erase: __pos (which is 18446744073709551615) > this->size() (which is 0)
Aborted (exit code 134)
```

The value `18446744073709551615` is `-1` cast to unsigned (std::string::npos). The VyOS CLI API is trying to parse or manipulate a string that doesn't exist, likely because the stuck FUSE mount is confusing the session detection logic.

## The Build Fix

### What Was Added

Created script: `scripts/vyos/cloud-init-wait-vyos.sh` which:
1. Installs polling script: `/usr/local/bin/wait-for-vyos-config.sh`
2. Creates systemd drop-in configuration: `/etc/systemd/system/cloud-final.service.d/wait-for-vyos.conf`

```bash
[Unit]
After=vyos-router.service
Wants=vyos-router.service

[Service]
ExecStartPre=/usr/local/bin/wait-for-vyos-config.sh
```

### How It Works

The polling script actively waits for VyOS configuration completion by monitoring `/tmp/vyos-config-status`:
- Polls every second for up to 60 seconds
- Checks if marker file exists and contains "0" (success)
- Exits immediately when configuration completes
- Provides diagnostic output on timeout

**Key improvement over fixed sleep:**
- vyos-router.service uses `Type=simple` which marks it as "started" immediately on fork
- `After=vyos-router.service` only ensures ordering (start after it begins), not completion
- VyOS configuration takes 16+ seconds to complete after service "starts"
- Active polling ensures cloud-init waits for **actual completion**, not just service start

Timeline:
```
~24s: vyos-router.service marked "started" by systemd
~24s: vyos-router script begins execution
~26s: /run/vyos-configd.sock created (daemon starts)
~40s: /tmp/vyos-config-status created with "0" (configuration completes)
~40s: Polling script detects completion and exits
~40s: cloud-init runs user scripts
Result: Configuration fully applied BEFORE user scripts run
```

### Added to Build Process

In `roles/vyos_build_image/templates/vyos_base.pkr.hcl.j2`:
- Script runs after cloud-init datasource configuration
- Before Azure Linux Agent installation
- Configures systemd during image build, active on first boot

## Verification

### Check if Fix is Applied

On a running VM, verify the polling script is installed:

```bash
ls -l /usr/local/bin/wait-for-vyos-config.sh
cat /etc/systemd/system/cloud-final.service.d/wait-for-vyos.conf
```

Expected output:
```bash
-rwxr-xr-x 1 root root ... /usr/local/bin/wait-for-vyos-config.sh

[Unit]
After=vyos-router.service
Wants=vyos-router.service

[Service]
ExecStartPre=/usr/local/bin/wait-for-vyos-config.sh
```

Verify the systemd ordering:

```bash
systemctl show cloud-final.service | grep -E "After=|Wants=|ExecStartPre=" | grep -E "vyos-router|wait-for-vyos"
```

Expected output:
```
After=... vyos-router.service ...
Wants=... vyos-router.service ...
ExecStartPre=... /usr/local/bin/wait-for-vyos-config.sh ...
```

### Check Boot Timeline

```bash
systemd-analyze blame | grep -E "(cloud|vyos)"
```

Should show cloud-final starting AFTER vyos-router completes.

### Check for Stuck Mounts

```bash
mount | grep vyatta
```

Should NOT show any `new_config_*` mounts except during active configure sessions.

## Resolution for Existing VMs

### Immediate Fix (This Deployment)

The stuck FUSE mount cannot be cleanly removed. **Reboot the VM**:

```bash
sudo reboot
```

After reboot:
- Stuck mount will be cleared
- If VM was built with new image, systemd ordering will be active
- Cloud-init should run successfully
- Configure mode should work

### Permanent Fix (Future Deployments)

Rebuild the image with the cloud-init-wait-vyos.sh fix included, then redeploy VMs from the new image.

### Manual Fix for VMs Built Without Fix

If you need to fix an existing VM that was built before the fix:

```bash
# Install the polling script
sudo tee /usr/local/bin/wait-for-vyos-config.sh <<'EOF'
#!/bin/bash
TIMEOUT=60
MARKER_FILE="/tmp/vyos-config-status"
echo "Waiting for VyOS configuration to complete..."
for i in $(seq 1 $TIMEOUT); do
    if [ -f "$MARKER_FILE" ] && [ "$(cat "$MARKER_FILE" 2>/dev/null)" = "0" ]; then
        echo "VyOS configuration completed successfully after $i seconds"
        exit 0
    fi
    sleep 1
done
echo "ERROR: Timeout waiting for VyOS configuration after $TIMEOUT seconds"
exit 1
EOF
sudo chmod +x /usr/local/bin/wait-for-vyos-config.sh

# Create systemd drop-in
sudo mkdir -p /etc/systemd/system/cloud-final.service.d
sudo tee /etc/systemd/system/cloud-final.service.d/wait-for-vyos.conf <<EOF
[Unit]
After=vyos-router.service
Wants=vyos-router.service

[Service]
ExecStartPre=/usr/local/bin/wait-for-vyos-config.sh
EOF
sudo systemctl daemon-reload
```

Then redeploy (or re-run cloud-init).

## Key Takeaways

1. **VyOS is unique**: Its config system initializes late in the boot process (16+ seconds after service starts)
2. **Cloud-init timing matters**: User scripts must wait for VyOS to be **fully ready**, not just service start
3. **Failed sessions leave artifacts**: Stuck FUSE mounts prevent future sessions
4. **Active polling is required**: systemd `After=` only ensures start ordering, not completion dependency
5. **Use marker files**: `/tmp/vyos-config-status` reliably indicates configuration completion
6. **Always test first boot**: This race condition only manifests on initial deployment

## Related Issues

- Serial console logs showing: `ERROR Daemon Daemon /proc/net/route contains no routes`
  - Same root cause: network config not applied yet during early boot
  - Fixed by same systemd ordering solution

- `show configuration` returns empty/default config
  - Cloud-init script never successfully applied configuration
  - All VyOS commands (interfaces, firewall, NAT) missing

- Waagent errors during boot
  - Can't reach Azure wireserver (168.63.129.16) without network
  - Resolves once network configuration is properly applied
