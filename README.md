# HomeLab Cluster Management

Automated NixOS + k3s cluster deployment and management system with declarative configuration and graceful scaling capabilities.

## 🚀 Quick Start

```bash
# 1. Edit your cluster configuration
vim cluster.json

# 2. Deploy entire cluster with confirmation prompts
./scripts/deploy-cluster.sh

# 3. Add/remove nodes by editing cluster.json and re-running deploy
```

## 📁 Project Structure

```text
HomeLab/
├── cluster.json                # 📋 Declarative cluster configuration
├── scripts/
│   ├── install-nuc.sh          # 🔧 One-time NixOS installation
│   ├── generate-configs.py     # ⚙️ Dynamic config generation
│   ├── cleanup-nodes.py        # 🧹 Graceful node removal
│   └── deploy-cluster.sh       # 🚀 Complete deployment workflow
├── common/
│   ├── common.nix              # Basic NixOS configuration (safe for all)
│   ├── k3s-cluster.nix         # k3s cluster-specific settings
│   └── deploy-rs.nix           # Deploy-rs automation settings
├── hosts/                      # 🏠 Auto-generated host configs
│   ├── nuc1/configuration.nix  # Host-specific config (server)
│   ├── nuc2/configuration.nix  # Host-specific config (agent)
│   └── nuc3/configuration.nix  # Host-specific config (agent)
├── flake.nix                   # 📦 Auto-generated Nix flake + deploy-rs
└── DESIGN.md                   # 📖 Architecture documentation
```

## 🛠️ Core Workflows

### 🚀 Complete Cluster Deployment

**Primary tool**: `./scripts/deploy-cluster.sh`

**What it does**:

- Generates configurations from `cluster.json`
- Validates with `nix flake check`
- Shows deployment plan with user confirmation
- Deploys to all nodes with `deploy-rs`
- Verifies SSH connectivity post-deployment

```bash
# Standard deployment
./scripts/deploy-cluster.sh

# Preview without changes
./scripts/deploy-cluster.sh --dry-run

# Remove nodes and deploy (with k3s cleanup)
./scripts/deploy-cluster.sh --cleanup-k3s

# Generate configs only (no deployment)
./scripts/deploy-cluster.sh --skip-deploy
```

### 📋 Cluster Configuration (`cluster.json`)

**Declarative configuration** - edit this file to define your entire cluster:

```json
{
  "domain": "homelab.local",
  "subnet": "192.168.1.0/24",
  "nodes": [
    {
      "name": "nuc1",
      "hostname": "nuc1", 
      "ip": "192.168.1.141",
      "role": "server",
      "description": "k3s control plane"
    },
    {
      "name": "nuc2",
      "hostname": "nuc2",
      "ip": "192.168.1.142", 
      "role": "agent",
      "description": "k3s worker node"
    }
  ],
  "server_config": { /* k3s server settings */ },
  "agent_config": { /* k3s agent settings */ }
}
```

**To scale**: Add/remove nodes in the `nodes` array and redeploy

### 🔧 Individual Tools

#### `scripts/install-nuc.sh` - NixOS Installation

**Purpose**: One-time installation of basic NixOS on fresh hardware

```bash
# Run from NixOS live installer environment
./scripts/install-nuc.sh -h nuc1
```

**What it does**:

- Partitions and formats drives (OS + NVMe data)
- Installs basic, secure NixOS with SSH access
- Uses only safe configuration (`common/common.nix`)

#### `scripts/generate-configs.py` - Dynamic Configuration

**Purpose**: Generate NixOS configurations from `cluster.json`

```bash
python3 scripts/generate-configs.py
```

**Features**:

- ✅ **Declarative**: Creates/updates/removes host configs automatically
- ✅ **Self-cleaning**: Removes old node directories not in cluster.json
- ✅ **Dynamic flake.nix**: Auto-generates deploy targets

#### `scripts/cleanup-nodes.py` - Graceful Node Removal

**Purpose**: Safely remove nodes from k3s cluster

```bash
# Preview what would be cleaned up
python3 scripts/cleanup-nodes.py --dry-run

# Actually clean up removed nodes
python3 scripts/cleanup-nodes.py
```

**What it does**:

1. 🔄 **Drains** workloads from removed nodes
2. 🗑️ **Deletes** nodes from k3s cluster
3. 🔌 **Stops** k3s services on removed nodes
4. 🧹 **Removes** k3s token files

---

### `deploy` (deploy-rs)

**Purpose**: Automated deployment of configurations to existing NixOS systems

## 🔄 Typical Workflows

### 🆕 Adding a New Node

1. **Install NixOS** on new hardware:

   ```bash
   ./scripts/install-nuc.sh -h nuc4
   ```

2. **Add to cluster.json**:

   ```json
   {
     "name": "nuc4",
     "hostname": "nuc4",
     "ip": "192.168.1.144", 
     "role": "agent",
     "description": "k3s worker node"
   }
   ```

3. **Deploy**:

   ```bash
   ./scripts/deploy-cluster.sh
   ```

### 🗑️ Removing a Node

1. **Remove from cluster.json** (delete the node entry)

2. **Deploy with cleanup**:

   ```bash
   ./scripts/deploy-cluster.sh --cleanup-k3s
   ```

This automatically:

- Drains workloads from the removed node
- Deletes it from k3s cluster
- Stops k3s services on the node

### 🔧 Configuration Changes

1. **Edit cluster.json** or common configuration files
2. **Deploy**: `./scripts/deploy-cluster.sh`
3. **Verify**: Check services are running correctly

## 📝 Configuration Files

### `common/common.nix`

**Purpose**: Basic, safe NixOS configuration for all systems

**Contains**:

- Basic system settings (boot loader, networking)
- SSH server configuration
- User account definition
- Safe defaults (root login disabled, password sudo)

**Used by**:

- Fresh installations (via install script)
- All managed systems (as base configuration)

**Safety**: ✅ Secure and safe for any installation

---

### `common/k3s-cluster.nix`

**Purpose**: k3s cluster-specific configuration

**Contains**:

- Firewall disabled for cluster communication
- NVMe data drive mounting
- k3s data directories
- Cluster management packages

**Used by**:

- Only systems managed by deploy-rs
- Only when joining k3s cluster

**Safety**: ⚠️ Only for cluster members (disables firewall)

---

### `common/deploy-rs.nix`

**Purpose**: Deploy-rs automation requirements

**Contains**:

- Root SSH access (for deployment)
- Passwordless sudo (for automation)
- Deploy-rs specific settings

**Used by**:

- Only systems managed by deploy-rs
- Required for automated deployments

**Safety**: ⚠️ Only for managed systems (reduces security for automation)

---

### `hosts/nucX/configuration.nix`

**Purpose**: Host-specific configuration for each NUC

**Contains**:

- Hostname setting
- k3s role (server vs agent)
- Hardware configuration import
- All common configurations import

**Used by**:

- Deploy-rs when managing specific hosts
- Defines the final system configuration

## 🔄 Workflow

### Phase 1: Fresh Installation

```text
1. Boot NUC from NixOS installer USB
2. Run: ./scripts/install-nuc.sh -h nuc1
3. Result: Basic, secure NixOS system
4. Access via: ssh -i ~/.ssh/nuc_homelab_id_ed25519 satya@<ip>
```

### Phase 2: Cluster Deployment

```text
1. Ensure all NUCs have basic NixOS installed
2. Run: ./scripts/deploy-cluster.sh
3. Set up k3s tokens (first deployment only)
4. Result: Full k3s cluster running
```

### 🔑 k3s Token Setup (First Deployment Only)

After initial deployment, worker nodes need the cluster token:

1. **Get token from server (nuc1)**:

   ```bash
   ssh satya@192.168.1.141 'sudo cat /var/lib/rancher/k3s/server/node-token'
   ```

2. **Place token on each worker node**:

   ```bash
   # For each worker (nuc2, nuc3, etc.)
   ssh satya@192.168.1.142
   sudo mkdir -p /etc/rancher/k3s
   echo "YOUR_TOKEN_HERE" | sudo tee /etc/rancher/k3s/agent-token
   sudo systemctl restart k3s-agent
   ```

3. **Verify cluster**:

   ```bash
   kubectl get nodes  # Should show all nodes Ready
   ```

## 🎯 Configuration Layers

Each managed system loads configurations in this order:

```text
hosts/nucX/configuration.nix
├── hardware-configuration.nix    # Generated during installation
├── common/common.nix             # Basic system (always safe)
├── common/k3s-cluster.nix        # Cluster settings (deploy-rs only)
└── common/deploy-rs.nix          # Automation settings (deploy-rs only)
```

## 🔒 Security Model

### Fresh Installations (via install script)

- ✅ Root login disabled
- ✅ Password sudo required
- ✅ SSH key-only authentication
- ✅ Standard firewall enabled

### Managed Systems (via deploy-rs)

- ⚠️ Root SSH access (for automation)
- ⚠️ Passwordless sudo (for automation)
- ⚠️ Firewall disabled (for cluster communication)
- ✅ SSH key-only authentication

## 🚨 Important Notes

### Do NOT use deploy-rs configs for fresh installs

- The `install-nuc.sh` script uses only safe configurations
- Deploy-rs configurations reduce security for automation
- Always install fresh systems with the install script first

### Do NOT manually edit installed systems

- All configuration should be done via git + deploy-rs
- Manual changes will be overwritten on next deployment
- Use declarative configuration management exclusively

### Token Management for k3s

- Server generates a token during first boot
- Agents need this token to join the cluster
- Token file: `/etc/rancher/k3s/agent-token` on worker nodes
- Retrieve from server: `sudo cat /var/lib/rancher/k3s/server/node-token`

## 📞 Common Commands

```bash
# Fresh installation
./scripts/install-nuc.sh -h nuc4

# Deploy cluster
deploy --remote-build .#nuc1 .#nuc2 .#nuc3

# Check cluster status
ssh nuc1 "sudo kubectl get nodes"

# Get k3s server token
ssh nuc1 "sudo cat /var/lib/rancher/k3s/server/node-token"

# View k3s logs
ssh nuc1 "sudo journalctl -u k3s -f"
```

## ✨ Key Features

### 🎯 **Declarative Configuration**

- **Single source of truth**: `cluster.json` defines entire cluster
- **Auto-generated configs**: NixOS configurations created automatically
- **Self-cleaning**: Removes old configurations when nodes are removed

### 🚀 **Automated Deployment**

- **One-command deployment**: `./scripts/deploy-cluster.sh`
- **User confirmation**: Shows deployment plan before executing
- **Validation**: Runs `nix flake check` before deployment
- **Post-deployment verification**: Confirms SSH connectivity

### 🧹 **Graceful Scaling**

- **Safe node addition**: Install → Edit JSON → Deploy
- **Graceful node removal**: Drains workloads → Removes from cluster → Stops services
- **k3s integration**: Automatically handles cluster membership

### 🔒 **Security Model**

- **Fresh installs**: Secure defaults (no root SSH, password sudo)
- **Managed systems**: Automation-friendly (root SSH, passwordless sudo)
- **Clear separation**: Install script vs. cluster management

### 🛠️ **Development Experience**

- **Preview mode**: `--dry-run` for all operations
- **Modular tools**: Each script has a specific purpose
- **Zero dependencies**: Uses built-in Python modules only

---

## 📚 Additional Resources

- **[DESIGN.md](DESIGN.md)** - Detailed architecture documentation
- **[cluster.json](cluster.json)** - Live cluster configuration
- **[common/](common/)** - Shared NixOS configuration modules
