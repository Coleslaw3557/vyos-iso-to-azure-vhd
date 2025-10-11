# VyOS Packer Build

Automated VyOS image builder using Ansible and Packer. Creates qcow2 images suitable for deployment to cloud platforms like Azure.

This was originally based off of 

https://github.com/rerichardjr/vyos-rolling-packer-build from rerichardjr as well as Uroesch / packer-linux convert-diskimage script. https://github.com/uroesch/packer-linux/blob/main/scripts/convert-diskimage.sh

Thank you!

Differences from their version:

- Optionally use the URL of an ISO instead of the latest nightly (in my case, quarterly stream iso).
- I run this over SSH to a headless Ubuntu server and had to make some minor changes as well as adjust some timers.
- The ansible playbook will convert the image into a cloud image (like vhd for azure).

This does NOT add in cloud init support IE you will need to configure this inside the VM (azure/gcp/aws settings will not propogate into vm).

Note: This was all glued together by Claude LLM. Sorry not sorry.
## Features

- Automated installation of dependencies (QEMU, Packer, minisign, jq)
- Support for both GitHub API (rolling releases) and static ISO URLs (stable/stream releases)
- Cryptographic verification of ISOs using minisign
- Configurable disk size (default: 20GB)
- Automated VyOS installation via VNC boot commands
- Automatic image conversion to VHD (Azure), VMDK (VMware), or other formats
- Serial console logging for debugging

## Requirements

- Ubuntu/Debian-based system
- Python 3 and Ansible
- Sudo access


## Quick Start

```bash
# Install Ansible
sudo apt update && sudo apt install -y ansible

# Clone repository
cd vyos-rolling-packer-build

# Run build
ansible-playbook build.yml
```

Build takes ~3-4 minutes. Output images in `/var/artifacts/images/`:

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

### Disk Size

Modify 
`roles/vyos_build_image/templates/vyos_base.pkr.hcl.j2`:
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

**Note:** This image does NOT include cloud-init or Azure VM agent. Configure the system manually after deployment or use Ansible provisioning (see Terraform example in docs).

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

**Note:** 
Don't connect before Packer starts typing commands (after 90s boot_wait) or it will interfere with automation.

### Test Built Image

**Quick boot test:**
Make a copy of the image and connect to that instead of the one you plan to push a cloud provider.
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


## Architecture

```
build.yml
├── install_apps        # Install QEMU, minisign, jq
├── install_packer      # Install HashiCorp Packer
├── vyos_get_files      # Download & verify ISO
├── vyos_build_image    # Run Packer build
│   └── vyos_base.pkr.hcl.j2  # Packer template
└── convert_image       # Convert qcow2 to other formats
    └── convert-diskimage.sh  # Conversion script
```

**Build Process:**
1. Wait 90s for VyOS live boot (VGA console ready ~70s)
2. Login via VNC keyboard input
3. Run `install image` with automated responses
4. Wait 90s for installation to complete
5. Execute `poweroff now`
6. Packer converts to final qcow2
7. Convert qcow2 to VHD/VMDK (if enabled)

## License

MIT License


