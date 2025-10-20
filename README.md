# VyOS Packer Build

Automated VyOS image builder using Ansible and Packer. Creates qcow2 image and converts to the cloud provider of your choice with cloud init or waagent (azure) added a build time. This is for personal use but I think this might help others so I'm throwing it out there. I've only tested with Azure using terraform but it's working well!

## Credits

This project was originally based on [rerichardjr/vyos-rolling-packer-build](https://github.com/rerichardjr/vyos-rolling-packer-build) as well as the [Uroesch/packer-linux convert-diskimage script](https://github.com/uroesch/packer-linux/blob/main/scripts/convert-diskimage.sh). The provisioning scripts were adapted from [vyos-contrib/packer-vyos](https://github.com/vyos-contrib/packer-vyos/tree/main/scripts/vyos).

Thank you!!

**Differences from the upstream version:**

- Optionally use the URL of an ISO instead of the latest nightly (supports quarterly stream ISOs)

- Optimized for headless Ubuntu server builds over SSH with adjusted timers

- The Ansible playbook automatically converts images to cloud formats (VHD for Azure, VMDK for VMware, etc.)

- **Cloud-init handles provisioning with Azure Linux Agent (waagent) managing Azure extensions**

- **Azure Linux Agent (walinuxagent) v2.14.0.1 installed from source for Azure extension support**

- **Added FRR service ordering to prevent configuration race conditions** (this may no longer be needed though).

**Note:** 
A lot of this was glued together with Claude LLM. 

## Features

- Automated installation of dependencies (QEMU, Packer, minisign, jq)
- Support for both GitHub API (rolling releases) and static ISO URLs (stable/stream releases)
- Cryptographic verification of ISOs using minisign (currently broken).
- Configurable disk size (default: 20GB)
- Automated VyOS installation via VNC boot commands and SSH.
- **Cloud-init for VM provisioning and configuration management**
- **Azure Linux Agent v2.14.0.1 for Azure extension support**
- **QEMU guest agent installation for Azure/KVM integration**
- **Azure serial console enabled by default (ttyS0 at 115200 baud)**. This needs to be turned on in boot diagnostics in azure first though.
- SSH-based provisioning for customization
- Automatic image conversion to VHD (Azure), VMDK (VMware), or other formats (I've only tested Azure)
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

### Azure Configuration

```yaml
# Azure Linux Agent configuration
waagent_version: "2.14.0.1"  # Specific version to install from source
```

**Cloud-init configuration:**

```yaml
cloud_init_source: "debian"  # Options: 'vyos' or 'debian'
vyos_release: "current"      # Options: 'equuleus', 'sagitta', 'circinus', 'current'
platform: "qemu"  # Install qemu-guest-agent for Azure/KVM
```

**Configuration options:**

- `cloud_init_source: "debian"` - Install cloud-init from Debian repositories (recommended for Stream builds)
- `cloud_init_source: "vyos"` - Install cloud-init from VyOS repositories (only available with VyOS LTS subscription)
- `vyos_release` must match your VyOS version:
  - `equuleus` - VyOS 1.3.x LTS (Debian 11)
  - `sagitta` - VyOS 1.4.x LTS (Debian 12) - **Requires VyOS subscription**
  - `current` - VyOS Stream/rolling releases (Debian 12) - **Use with Stream ISOs**
  - `circinus` - VyOS development (future release)

**Important:** 
VyOS has restricted access to LTS package repositories (equuleus, sagitta) for paying subscribers only. For Stream builds (1.5-stream), use `cloud_init_source: "debian"` and `vyos_release: "current"` to avoid repository access issues.

**Azure Provisioning:** 

For Azure deployments, the build installs both cloud-init and waagent:
- Cloud-init handles all provisioning tasks (SSH keys, user-data, initial configuration)
- Waagent is configured with `Provisioning.Agent=cloud-init` to defer provisioning to cloud-init
- Waagent manages Azure-specific extensions (monitoring, diagnostics, etc.)
- Azure datasource is configured with `apply_network_config: false` to let VyOS manage network
- Cloud-init starts waagent after provisioning via `agent_command`

**Important**: The image is properly generalized during build using `waagent -deprovision+user -force` to ensure it's ready for Azure provisioning.

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

**Provisioning Support:** This build uses cloud-init as the primary provisioning agent with Azure Linux Agent (walinuxagent v2.14.0.1) for Azure extensions support. Both agents are installed and configured to work together:
- Cloud-init handles initial provisioning (SSH keys, user-data, configuration)
- Waagent manages Azure-specific extensions and features
- The Azure datasource is configured with network management disabled to let VyOS handle its own network

**Important:** The build installs **WALinux Agent v2.14.0.1** from GitHub source to ensure the latest features and compatibility. Waagent is configured with `Provisioning.Agent=cloud-init` to defer provisioning to cloud-init while managing Azure extensions. The image is properly generalized with `waagent -deprovision+user -force` during the build cleanup phase.

**Azure Serial Console:** The image is configured with serial console support enabled by default (ttyS0 at 115200 baud, 8N1). You can access the console through Azure Portal → VM → Serial Console or via Azure CLI. Both GRUB bootloader output and login prompt are available on the serial console for troubleshooting boot issues.

**Cloud-Init Race Condition Fix:** VyOS has a unique boot process where the config system mounts and applies configuration 16+ seconds after `vyos-router.service` starts. The build adds an active polling script that monitors `/tmp/vyos-config-status` to detect when VyOS configuration actually completes (not just when the service starts). Systemd ordering ensures `cloud-final.service` waits for `vyos-router.service` to start, then the polling script waits for actual configuration completion before allowing cloud-init user scripts to run. This prevents a race condition where cloud-init finishes before VyOS applies the config, leaving the VM without network connectivity during initial boot.

**FRR Service Ordering:** The build uses a **dual-layer approach** to ensure FRR is ready before network configuration:

  1. **Pre-configuration script** (`/opt/vyatta/etc/config/scripts/vyos-preconfig-bootup.script`): Runs before any VyOS configuration happens. Ensures FRR is started and verifies it's operational by connecting to the zebra daemon. Waits up to 30 seconds and logs status via syslog.

  2. **Systemd dependency** (`/etc/systemd/system/cloud-init.service.d/wait-for-frr.conf`): Uses `After=frr.service` for startup ordering and `Wants=frr.service` (soft dependency) as a safety net. Allows boot to proceed even if FRR encounters issues, ensuring the VM remains accessible for debugging.

  This defense-in-depth approach prevents race conditions where cloud-init attempts to configure network interfaces before FRR daemons are operational.
  
  
These systemctl ordering items have room for improvement... once I got it working I didn't want to go back and mess with it further.

## Development

### Watch Build Process via VNC

During build, Packer displays VNC connection info but don't do it when ansible is connected or you will kill the session.
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

### Troubleshooting Azure Provisioning Issues

If you experience problems with Azure VMs failing to provision, check these items:

**Verify waagent configuration:**

```bash
# Check the provisioning agent setting
grep "Provisioning.Agent" /etc/waagent.conf
# Should show: Provisioning.Agent=cloud-init

# Check waagent service status
sudo systemctl status walinuxagent
sudo journalctl -u walinuxagent -n 100

# Check if waagent is reporting ready to Azure
sudo cat /var/log/waagent.log | grep -i "provisioning"
```

**Common provisioning issues:**

1. **Wrong Provisioning.Agent setting**: Should be `cloud-init` since cloud-init handles provisioning
2. **Image not deprovisioned**: If the image wasn't properly generalized with `waagent -deprovision+user -force`, Azure may fail to provision correctly
3. **Service not running**: Ensure both cloud-init and walinuxagent.service are enabled and running

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
7. **Install cloud-init:**
   - Install cloud-init packages from Debian repositories
   - Configure Azure datasource with apply_network_config=false
   - Configure cloud-init with VyOS-compatible modules only
   - Add systemd ordering (cloud-final waits for vyos-router)
8. **Install Azure Linux Agent (waagent):**
   - Install walinuxagent v2.14.0.1 from GitHub source
   - Configure waagent with Provisioning.Agent=cloud-init
   - Waagent manages Azure extensions only
9. Install qemu-guest-agent
10. Configure Azure serial console (GRUB + getty on ttyS0)
11. System cleanup and optimization:
    - Run `waagent -deprovision+user -force` to generalize for Azure
    - Remove SSH host keys, machine-id, logs, and history
    - Zero out free disk space
12. Shutdown and convert to final qcow2
13. Convert qcow2 to VHD/VMDK (if enabled)

## License

MIT License
