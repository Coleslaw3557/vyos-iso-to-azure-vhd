# VyOS Rolling Packer Build

This Ansible project automates the creation of VyOS rolling builds using Packer. It installs necessary dependencies, downloads and verifies the VyOS ISO file, generates a Packer configuration from a template, and saves all artifacts in a designated folder.

---

## **Features**
- **Automated Dependency Installation**: Installs `qemu`, `minisign`, and `packer`.
- **ISO Retrieval**: Fetches the latest VyOS rolling ISO and minisign signature from GitHub API.
- **ISO Verification**: Verifies the ISO integrity using the VyOS public key and Minisign.
- **Packer Configuration**: Generates a Packer HCL configuration from a Jinja2 template.
- **Artifact Management**: Saves generated files and artifacts to `/var/artifacts`.

---

## **Folder Structure**
```bash
.
├── build.yml           # Main Ansible playbook
├── roles/              # Role-based tasks and logic
│   ├── install_apps/   # Installs system dependencies
│   ├── install_packer/ # Manages Packer installation
│   ├── vyos_build_image/ # Handles Packer build steps
│   └── vyos_get_files/ # Downloads VyOS ISO and minisign files
├── vars.yml            # Global variables for the playbook
```

### **Role Breakdown**
1. **`install_apps`**:
   - Installs `qemu` and `minisign` packages required for the build process.

2. **`install_packer`**:
   - Installs Packer and ensures it is properly configured.

3. **`vyos_get_files`**:
   - Fetches the latest VyOS ISO and minisign signature via GitHub API.
   - Validates download integrity using Minisign and the VyOS public key.

4. **`vyos_build_image`**:
   - Generates a Packer configuration using the `vyos_base.pkr.hcl.j2` template.
   - Executes the Packer build to create VyOS base images.

---

## **Requirements**
- **System**: Ubuntu or any Debian-based OS
- **Tools**:
  - Python and Ansible
  - `qemu`
  - `packer`
  - `minisign`

---

## **Setup**
1. Clone the repository:
   ```bash
   git clone https://github.com/rerichardjr/vyos-rolling-packer-build.git
   cd vyos-rolling-packer-build
   ```

2. Install Ansible:
   ```bash
   sudo apt update && sudo apt install -y ansible
   ```

3. Configure Variables:
   - Update `vars.yml` to specify paths and configurations as needed.

---

## **Usage**
Run the playbook using:
```bash
ansible-playbook build.yml
```

---

## **Output**
Generated files and artifacts (including the VyOS base image and Packer configurations) are saved to:
```bash
/var/artifacts/
```

---

## **API Integration**
This playbook uses GitHub's API endpoint to fetch the latest VyOS release metadata:
```plaintext
https://api.github.com/repos/vyos/vyos-nightly-build/releases/latest
```

---

## **License**
This project is distributed under the [MIT License](LICENSE).

---

## **Contributing**
Feel free to open issues and submit pull requests for improvements and new features.