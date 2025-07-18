#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}🏠 HomeLab Cluster Deployment${NC}"
    echo "=================================="
}

print_step() {
    echo -e "\n${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Parse arguments
DRY_RUN=false
CLEANUP_K3S=false
SKIP_DEPLOY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --cleanup-k3s)
            CLEANUP_K3S=true
            shift
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--cleanup-k3s] [--skip-deploy]"
            echo ""
            echo "Options:"
            echo "  --dry-run      Show what would be done without making changes"
            echo "  --cleanup-k3s  Cleanup removed nodes from k3s cluster"
            echo "  --skip-deploy  Only generate configs, don't deploy"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
done

print_header

# Step 1: Generate configurations
print_step "Generating configurations from cluster.json"
if [ "$CLEANUP_K3S" = true ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "Note: --dry-run with --cleanup-k3s will only show k3s cleanup preview"
        python3 scripts/generate-configs.py
        echo ""
        echo "🧹 k3s cleanup preview:"
        python3 scripts/cleanup-nodes.py --dry-run
    else
        echo "⚠️  k3s cleanup mode enabled - removed nodes will be cleaned from cluster"
        python3 scripts/generate-configs.py
        echo ""
        echo "🧹 Running k3s cluster cleanup..."
        python3 scripts/cleanup-nodes.py
    fi
else
    python3 scripts/generate-configs.py
fi
print_success "Configuration generation complete"

# Step 2: Validate with nix flake check
if [ "$DRY_RUN" = false ]; then
    print_step "Validating configurations with nix flake check"
    if nix flake check; then
        print_success "Configuration validation passed"
    else
        print_error "Configuration validation failed"
        exit 1
    fi
fi

# Step 3: Deploy (unless skipped)
if [ "$SKIP_DEPLOY" = false ] && [ "$DRY_RUN" = false ]; then
    print_step "Preparing deployment to cluster nodes"
    
    # Read cluster.json to get node details
    echo "📋 Deployment Plan:"
    python3 -c "
import json
with open('cluster.json') as f:
    config = json.load(f)

print('  Nodes to deploy:')
for node in config['nodes']:
    role_icon = '🎛️' if node['role'] == 'server' else '⚙️'
    print(f'    {role_icon} {node[\"name\"]} ({node[\"ip\"]}) - {node[\"description\"]}')

nodes = [node['name'] for node in config['nodes']]
print(f'\\n  Deploy command: deploy --remote-build {\" \".join(f\".#{node}\" for node in nodes)}')
"
    
    echo ""
    read -p "🤔 Proceed with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Deployment cancelled by user"
        exit 1
    fi
    
    print_step "Deploying to cluster nodes"
    
    # Get nodes for deploy command
    nodes=$(python3 -c "
import json
with open('cluster.json') as f:
    config = json.load(f)
nodes = [node['name'] for node in config['nodes']]
print(' '.join(f'.#{node}' for node in nodes))
")
    
    if deploy --remote-build "$nodes"; then
        print_success "Deployment complete"
    else
        print_error "Deployment failed"
        exit 1
    fi
    
    print_step "Post-deployment verification"
    echo "Checking SSH connectivity..."
    
    # Verify SSH connectivity
    python3 -c "
import json, subprocess, sys
with open('cluster.json') as f:
    config = json.load(f)

all_good = True
for node in config['nodes']:
    name, ip = node['name'], node['ip']
    try:
        subprocess.run([
            'ssh', '-i', f'{str(__import__(\"pathlib\").Path.home())}/.ssh/nuc_homelab_id_ed25519',
            '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=no',
            f'satya@{ip}', 'echo \"✅ {name} ({ip}) is accessible\"'
        ], check=True, capture_output=True)
    except subprocess.CalledProcessError:
        print(f'❌ {name} ({ip}) is not accessible')
        all_good = False

if not all_good:
    sys.exit(1)
"
    
    print_success "All nodes are accessible"
    
elif [ "$DRY_RUN" = true ]; then
    print_step "DRY RUN: Would deploy to cluster nodes"
    # Read cluster.json to get node list
    nodes=$(python3 -c "
import json
with open('cluster.json') as f:
    config = json.load(f)
nodes = [node['name'] for node in config['nodes']]
print(' '.join(f'.#{node}' for node in nodes))
")
    echo "[DRY RUN] Would run: deploy --remote-build $nodes"
fi

# Final summary
echo ""
echo "🎉 Deployment workflow complete!"
echo ""
echo "Next steps:"
if [ "$SKIP_DEPLOY" = false ] && [ "$DRY_RUN" = false ]; then
    echo "1. Set up k3s tokens (if first deployment):"
    echo "   ssh satya@192.168.1.141 'sudo cat /var/lib/rancher/k3s/server/node-token'"
    echo "2. Verify cluster: kubectl get nodes"
    echo "3. Check pods: kubectl get pods -A"
else
    echo "1. Review generated configurations in hosts/"
    echo "2. Run: $0  # Deploy the cluster"
fi
