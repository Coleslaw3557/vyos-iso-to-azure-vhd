# VyOS Packer Build

Automated VyOS image builder using Ansible and Packer. Creates qcow2 images suitable for deployment to cloud platforms like Azure.

## Credits

This project was originally based on [rerichardjr/vyos-rolling-packer-build](https://github.com/rerichardjr/vyos-rolling-packer-build) as well as the [Uroesch/packer-linux convert-diskimage script](https://github.com/uroesch/packer-linux/blob/main/scripts/convert-diskimage.sh). The provisioning scripts were adapted from [vyos-contrib/packer-vyos](https://github.com/vyos-contrib/packer-vyos/tree/main/scripts/vyos).

Thank you to these contributors!

**Differences from the original version:**
- Optionally use the URL of an ISO instead of the latest nightly (supports quarterly stream ISOs)
- Optimized for headless Ubuntu server builds over SSH with adjusted timers
- The Ansible playbook automatically converts images to cloud formats (VHD for Azure, VMDK for VMware, etc.)
- **Configurable provisioning agent: Azure Linux Agent (waagent) or cloud-init**
- **Integrated Azure Linux Agent (walinuxagent) v2.14.0.1 installed from source for proper Azure provisioning**
- **Added FRR service ordering to prevent configuration race conditions**

**Note:** This project was assembled and enhanced with assistance from Claude AI.

## Features

- Automated installation of dependencies (QEMU, Packer, minisign, jq)
- Support for both GitHub API (rolling releases) and static ISO URLs (stable/stream releases)
- Cryptographic verification of ISOs using minisign
- Configurable disk size (default: 20GB)
- Automated VyOS installation via VNC boot commands
- **Configurable provisioning: Azure Linux Agent (waagent - default) or cloud-init**
- **Azure Linux Agent v2.14.0.1 installed from source for proper Azure provisioning**
- **QEMU guest agent installation for Azure/KVM integration**
- **Azure serial console enabled by default (ttyS0 at 115200 baud)**
- SSH-based provisioning for customization
- Automatic image conversion to VHD (Azure), VMDK (VMware), or other formats
- Serial console logging for debugging

## Requirements

- Ubuntu/Debian-based system
- Python 3 and Ansible
- Sudo access
- KVM virtualization support
- ~25GB free space for build artifacts (ISO + images + temporary files)

## Quick Start

```bash
# Install Ansible
sudo apt update && sudo apt install -y ansible

# Clone repository
git clone https://github.com/rerichardjr/vyos-rolling-packer-build.git
cd vyos-rolling-packer-build

# Run build
ansible-playbook build.yml
```

Build takes ~9-10 minutes. Output images in `/var/artifacts/images/`:
- `vyos-*.qcow2` - QEMU/KVM image
- `vyos-*-generic.vhd` - Azure-ready VHD (fixed format)

## Configuration

Edit `vars.yml` to customize:

### ISO Source Mode

**Static URL (recommended for stable releases):**
```yaml
iso_source_mode: "static_url"
static_iso_url: "https://community-downloads.vyos.dev/stream/1.5-stream-2025-Q2/vyos-1.5-stream-2025-Q2-generic-amd64.iso"
static_iso_sig_url: "https://community-downloads.vyos.dev/stream/1.5-stream-2025-Q2/vyos-1.5-stream-2025-Q2-generic-amd64.iso.minisig"
static_iso_filename: "vyos-1.5-stream-2025-Q2-generic-amd64.iso"
static_tag_name: "1.5-stream-2025-Q2"
```

**GitHub API (for rolling releases):**
```yaml
iso_source_mode: "github_api"
```

### Image Conversion

**Enable/disable automatic conversion:**
```yaml
convert_images: true  # Set to false to skip conversion
```

**Specify output formats:**
```yaml
conversion_formats:
  - vhd   # Azure, Hyper-V (fixed format)
  - vmdk  # VMware (streamOptimized)
  - vhdx  # Azure, Hyper-V (dynamic)
  - gcp   # Google Cloud Platform (tar.gz)
```

**Note:** VHD format uses fixed subformat and MB-alignment required by Azure.

### Provisioning Agent Configuration

**Choose provisioning agent (waagent or cloud-init):**
```yaml
# Options: 'waagent' (Azure Linux Agent only) or 'cloud-init' (cloud-init with optional waagent)
provisioning_agent: "waagent"  # Default: waagent

# Azure Linux Agent configuration
waagent_version: "2.14.0.1"  # Specific version to install from source
```

**Supported provisioning agents:**
- `provisioning_agent: "waagent"` - **Default**. Installs Azure Linux Agent as the standalone provisioning agent. Recommended for Azure deployments to avoid conflicts between cloud-init and waagent. Waagent is configured with `Provisioning.Agent=auto`.
- `provisioning_agent: "cloud-init"` - Installs cloud-init as the primary provisioning agent. Optionally installs waagent alongside cloud-init if `cloud_init_with_waagent: true` (not recommended). When both are installed, waagent is configured with `Provisioning.Agent=cloud-init`.

**Cloud-init configuration (only used when provisioning_agent is 'cloud-init'):**
```yaml
cloud_init_source: "debian"  # Options: 'vyos' or 'debian'
vyos_release: "current"      # Options: 'equuleus', 'sagitta', 'circinus', 'current'
cloud_init_datasource: "azure"  # Options: 'azure', 'nocloud_configdrive', 'azure_fallback'
cloud_init_with_waagent: false  # Install waagent alongside cloud-init (not recommended)
platform: "qemu"  # Install qemu-guest-agent for Azure/KVM
```

**Cloud-init options:**
- `cloud_init_source: "debian"` - Install cloud-init from Debian repositories (recommended for Stream builds)
- `cloud_init_source: "vyos"` - Install cloud-init from VyOS repositories (only available with VyOS LTS subscription)
- `vyos_release` must match your VyOS version:
  - `equuleus` - VyOS 1.3.x LTS (Debian 11)
  - `sagitta` - VyOS 1.4.x LTS (Debian 12) - **Requires VyOS subscription**
  - `current` - VyOS Stream/rolling releases (Debian 12) - **Use with Stream ISOs**
  - `circinus` - VyOS development (future release)
- `cloud_init_datasource` options:
  - `azure` - Use Azure datasource (recommended for Azure deployment)
  - `nocloud_configdrive` - Use NoCloud and ConfigDrive datasources (for testing/other clouds)
  - `azure_fallback` - Try Azure first, fall back to NoCloud/ConfigDrive
- `cloud_init_with_waagent` - Install both cloud-init and waagent:
  - `false` - **Default**. Cloud-init only (recommended)
  - `true` - Install waagent alongside cloud-init (may cause conflicts)

**Important:** VyOS has restricted access to LTS package repositories (equuleus, sagitta) for paying subscribers only. For Stream builds (1.5-stream), use `cloud_init_source: "debian"` and `vyos_release: "current"` to avoid repository access issues.

**Azure Provisioning:** For Azure deployments, **waagent is strongly recommended** as the standalone provisioning agent. Azure expects waagent to report provisioning status. The default configuration (`provisioning_agent: "waagent"`) installs **WALinux Agent v2.14.0.1** from source and configures it as the primary provisioning agent with `Provisioning.Agent=auto`. This avoids conflicts that can occur when both cloud-init and waagent are installed.

### Disk Size

Modify `roles/vyos_build_image/templates/vyos_base.pkr.hcl.j2`:
```hcl
disk_size = "20G"  # Adjust as needed
```

## Azure Deployment

The build automatically creates an Azure-ready VHD in fixed format:
```
/var/artifacts/images/vyos-*-generic.vhd
```

**Upload to Azure:**
1. Upload VHD to Azure Storage Account
2. Create managed disk from VHD
3. Create VM from managed disk or add to Azure Compute Gallery

**Default credentials:** `vyos` / `vyos`

**Provisioning Support:** By default, this build installs Azure Linux Agent (walinuxagent v2.14.0.1) as the standalone provisioning agent, along with qemu-guest-agent for proper integration with Azure. The provisioning agent is injected into the image **before first boot**, ensuring proper initialization and provisioning status reporting to Azure.

**Important:** The build installs **WALinux Agent v2.14.0.1** from source (not from Debian repos) to ensure the latest features and compatibility. When using waagent as the standalone provisioning agent (default), it is configured with `Provisioning.Agent=auto`. If you choose cloud-init mode with waagent enabled, it will be configured with `Provisioning.Agent=cloud-init`.

**Azure Serial Console:** The image is configured with serial console support enabled by default (ttyS0 at 115200 baud, 8N1). You can access the console through Azure Portal → VM → Serial Console or via Azure CLI. Both GRUB bootloader output and login prompt are available on the serial console for troubleshooting boot issues.

**Cloud-Init Race Condition Fix (cloud-init mode only):** VyOS has a unique boot process where the config system mounts and applies configuration 16+ seconds after `vyos-router.service` starts. When using cloud-init as the provisioning agent, the build adds an active polling script that monitors `/tmp/vyos-config-status` to detect when VyOS configuration actually completes (not just when the service starts). Systemd ordering ensures `cloud-final.service` waits for `vyos-router.service` to start, then the polling script waits for actual configuration completion before allowing cloud-init user scripts to run. This prevents a race condition where cloud-init finishes before VyOS applies the config, leaving the VM without network connectivity during initial boot.

**FRR Service Ordering:** The build uses a **dual-layer approach** to ensure FRR is ready before network configuration:

  1. **Pre-configuration script** (`/opt/vyatta/etc/config/scripts/vyos-preconfig-bootup.script`): Runs before any VyOS configuration happens. Ensures FRR is started and verifies it's operational by connecting to the zebra daemon. Waits up to 30 seconds and logs status via syslog.

  2. **Systemd dependency** (`/etc/systemd/system/cloud-init.service.d/wait-for-frr.conf`): Uses `After=frr.service` for startup ordering and `Wants=frr.service` (soft dependency) as a safety net. Allows boot to proceed even if FRR encounters issues, ensuring the VM remains accessible for debugging.

  This defense-in-depth approach prevents race conditions where cloud-init attempts to configure network interfaces before FRR daemons are operational.

## Development

### Watch Build Process via VNC

During build, Packer displays VNC connection info:
```
==> qemu.vyos_rolling: vnc://0.0.0.0:5915
```

**SSH Port Forward (from local machine):**
```bash
ssh -L 5915:localhost:5915 user@build-server
```

**Connect VNC client:**
```
localhost:5915
```

**Note:** Don't connect before Packer starts typing commands (after 90s boot_wait) or it will interfere with automation.

### Test Built Image

**Quick boot test:**
```bash
sudo qemu-system-x86_64 \
  -m 2048 \
  -drive file=/var/artifacts/images/vyos-*.qcow2,format=qcow2 \
  -serial mon:stdio \
  -nographic
```

Login: `vyos` / `vyos` (first boot takes ~10 minutes)

**VNC test (see VGA console):**
```bash
sudo qemu-system-x86_64 \
  -m 2048 \
  -drive file=/var/artifacts/images/vyos-*.qcow2,format=qcow2 \
  -vnc :0
```

Connect VNC to `localhost:5900`

### Debug Serial Console

Monitor installation progress:
```bash
tail -f /var/artifacts/serial.log
```

**Note:** VGA console (tty1) appears ~70 seconds after boot. Serial console (ttyS0) appears ~5 seconds after boot. Packer sends commands to VGA.

### Clean Build

Delete old artifacts and rebuild:
```bash
sudo rm -rf /var/artifacts/images/*
ansible-playbook build.yml
```

## Troubleshooting

**Build hangs at "Waiting for shutdown"**
- VNC connection may be blocking Packer (only 1 VNC client allowed)
- Boot commands may be out of sync (check boot_wait timing)

**"Failed to shutdown" after 8 minutes**
- Installation didn't complete (not enough wait time)
- Check serial log for errors

**Empty/corrupt qcow2 (< 500MB)**
- Installation failed - delete and rebuild
- Increase `<wait90>` in boot_command if needed

**VNC "Error handshaking"**
- Another VNC client is already connected
- Wait for Packer to disconnect, then retry

**"Invalid for APT::Default-Release" or VyOS repository errors**
- VyOS has restricted access to LTS repositories (sagitta, equuleus) for paying subscribers
- For Stream builds, use `cloud_init_source: "debian"` and `vyos_release: "current"` in vars.yml
- Debian's cloud-init works perfectly with VyOS and is fully supported

**SSH disconnects during provisioning / "Script disconnected unexpectedly"**
- Check `/var/artifacts/serial.log` for kernel panics or system errors
- Verify sufficient disk space and memory (minimum 2GB RAM, 20GB disk)
- Ensure `PACKER_HTTP_ADDR` environment variable is being passed correctly to provisioning scripts

**Azure provisioning timeout / "VM did not report ready"**
- Ensure `provisioning_agent: "waagent"` in vars.yml (default)
- Verify walinuxagent was installed during build (check build logs for "Installing Azure Linux Agent")
- If using cloud-init mode, ensure `cloud_init_datasource: "azure"` is set
- In Terraform, you can increase timeout: `timeouts { create = "60m" }`
- Check Azure serial console/boot diagnostics for waagent logs

**"No space left on device" during cleanup**
- This is **normal and expected** - the cleanup script intentionally fills the disk with zeros for better compression
- Build will continue normally after this message

**"Failed to set up config session" after Azure deployment**
- This indicates FRR (Free Range Routing) was not running when VyOS tried to configure interfaces
- **Root cause:** Race condition where cloud-init configured network before FRR daemons were operational
- **Fixed in build:** The build now uses a dual-layer approach:
  1. Enables FRR service: `systemctl enable frr` (in `scripts/vyos/osprep.sh`)
  2. Creates pre-config script: `/opt/vyatta/etc/config/scripts/vyos-preconfig-bootup.script` that ensures FRR is operational before any VyOS configuration happens
  3. Adds systemd dependency: cloud-init waits for FRR via `/etc/systemd/system/cloud-init.service.d/wait-for-frr.conf` with `Wants=frr.service` (soft dependency) to prevent boot failures
- **Debug on VM:** Check pre-config script logs: `sudo grep vyos-preconfig /var/log/syslog` or `sudo journalctl -t vyos-preconfig`
- **If using older image:** Manually verify FRR is enabled: `sudo systemctl is-enabled frr` and check dependencies: `systemctl show cloud-init.service | grep -E "After=|Wants="` should show `frr.service`
- **Temporary fix for existing VM:** `sudo systemctl enable frr && sudo systemctl start frr && sudo reboot`

**"can't initialize output" errors in configure mode**
- This error appears when running `set` commands in VyOS configure mode
- **Root cause:** Incorrect permissions on `/var/log/vyatta` directory prevent VyOS CLI from writing configuration logs
- **Fixed in build:** The build now sets proper permissions: `chown -R root:vyattacfg /var/log/vyatta && chmod -R 775 /var/log/vyatta` (in `scripts/vyos/osprep.sh`)
- **Manual fix for existing VM:**
  ```bash
  sudo chown -R root:vyattacfg /var/log/vyatta
  sudo chmod -R 775 /var/log/vyatta
  ```

**"ERROR Daemon Daemon /proc/net/route contains no routes" on first boot**
- This error appears in waagent logs during initial VM boot in Azure
- **Root cause:** Race condition where cloud-init finishes before VyOS applies network configuration
- **Symptoms:**
  - Cloud-init finishes at ~25 seconds into boot
  - VyOS config doesn't apply until ~37 seconds
  - No network routes during 12-second gap
  - Waagent repeatedly fails to reach Azure wireserver (168.63.129.16)
- **Fixed in build:** Active polling script added via `/usr/local/bin/wait-for-vyos-config.sh` that monitors `/tmp/vyos-config-status` for configuration completion. Systemd ordering via `/etc/systemd/system/cloud-final.service.d/wait-for-vyos.conf` ensures cloud-final waits for vyos-router.service then polls for actual configuration completion (not just service start)
- **Check if fix is applied:**
  ```bash
  ls -l /usr/local/bin/wait-for-vyos-config.sh
  systemctl show cloud-final.service | grep -E "After=|Wants=|ExecStartPre=" | grep -E "vyos-router|wait-for-vyos"
  ```
- **Manual fix for existing VM:**
  ```bash
  # Install polling script
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

## Diagnosing Cloud-Init and Configuration Issues

If you encounter issues with cloud-init not applying configuration or VyOS configure mode failing after deployment, use these diagnostic commands:

### Check Cloud-Init Status

**Check if cloud-init ran and its status:**
```bash
cloud-init status --long
```

**View cloud-init logs (shows what happened during execution):**
```bash
sudo cat /var/log/cloud-init.log | grep -i error
sudo cat /var/log/cloud-init.log | grep -i fail
sudo cat /var/log/cloud-init-output.log | tail -100
```

**See the actual script cloud-init ran:**
```bash
sudo cat /var/lib/cloud/instance/scripts/part-001
```

**View user-data that was provided:**
```bash
sudo cat /var/lib/cloud/instance/user-data.txt
```

### Check VyOS Configuration System

**Check for stuck VyOS configuration sessions:**
```bash
mount | grep vyatta
ps aux | grep unionfs
ls -la /opt/vyatta/config/tmp/
```

**Check current VyOS configuration:**
```bash
show configuration commands | grep firewall
show configuration commands | grep nat
show configuration
```

**Check VyOS configd status:**
```bash
sudo systemctl status vyos-configd
sudo journalctl -u vyos-configd -n 50
```

### Check Azure WALinux Agent

**Check waagent logs (Azure agent):**
```bash
sudo journalctl -u walinuxagent -n 100
sudo cat /var/log/waagent.log | tail -100
```

### Check System Logs

**Check system logs around the time cloud-init ran:**
```bash
sudo journalctl --since "05:40" --until "05:45" | grep -E "(error|fail|vyos)"
```

**Note:** Adjust the `--since` and `--until` times to match when your VM was provisioned.

## Architecture

```
build.yml
├── install_apps        # Install QEMU, minisign, jq
├── install_packer      # Install HashiCorp Packer
├── vyos_get_files      # Download & verify ISO
├── vyos_build_image    # Run Packer build
│   ├── vyos_base.pkr.hcl.j2  # Packer template with cloud-init provisioners
│   └── scripts/vyos/         # Cloud-init installation scripts
└── convert_image       # Convert qcow2 to other formats
    └── convert-diskimage.sh  # Conversion script
```

**Build Process:**
1. Wait 90s for VyOS live boot (VGA console ready ~70s)
2. Login via VNC keyboard input
3. Run `install image` with automated responses
4. Wait 90s for installation to complete
5. Reboot into installed system
6. Packer connects via SSH (vyos/vyos)
7. **Provisioning agent installation:**
   - **If provisioning_agent: "waagent" (default):**
     - Install Azure Linux Agent (walinuxagent v2.14.0.1 from source)
     - Configure waagent with Provisioning.Agent=auto
   - **If provisioning_agent: "cloud-init":**
     - Install cloud-init packages
     - Configure Azure datasource
     - Add systemd ordering (cloud-final waits for vyos-router)
     - Optionally install waagent if cloud_init_with_waagent: true
8. Install qemu-guest-agent
9. Configure Azure serial console (GRUB + getty on ttyS0)
10. System cleanup and optimization
11. Shutdown and convert to final qcow2
12. Convert qcow2 to VHD/VMDK (if enabled)

## License

MIT License
