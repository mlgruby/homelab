#!/usr/bin/env python3
"""
Cleanup removed nodes from k3s cluster

This script:
1. Reads cluster.json to get expected nodes
2. Queries k3s cluster to get actual nodes  
3. Gracefully removes nodes that are no longer in cluster.json
4. Stops k3s services on removed nodes

Usage: python3 scripts/cleanup-nodes.py [--dry-run]
"""

import json
import subprocess
import sys
import argparse
from pathlib import Path

def load_cluster_config():
    """Load cluster configuration from cluster.json"""
    with open('cluster.json', 'r') as f:
        return json.load(f)

def get_k3s_nodes():
    """Get list of nodes from k3s cluster"""
    try:
        result = subprocess.run(
            ['kubectl', 'get', 'nodes', '-o', 'json'],
            capture_output=True, text=True, check=True
        )
        nodes_data = json.loads(result.stdout)
        return {node['metadata']['name'] for node in nodes_data['items']}
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to get k3s nodes: {e}")
        return set()
    except json.JSONDecodeError:
        print("❌ Failed to parse kubectl output")
        return set()

def drain_node(node_name, dry_run=False):
    """Drain a node to move workloads off it"""
    cmd = ['kubectl', 'drain', node_name, '--ignore-daemonsets', '--delete-emptydir-data', '--force']
    
    if dry_run:
        print(f"[DRY RUN] Would drain node: {' '.join(cmd)}")
        return True
        
    print(f"🔄 Draining node {node_name}...")
    try:
        subprocess.run(cmd, check=True)
        print(f"✅ Successfully drained {node_name}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to drain {node_name}: {e}")
        return False

def delete_node(node_name, dry_run=False):
    """Delete a node from k3s cluster"""
    cmd = ['kubectl', 'delete', 'node', node_name]
    
    if dry_run:
        print(f"[DRY RUN] Would delete node: {' '.join(cmd)}")
        return True
        
    print(f"🗑️  Deleting node {node_name} from cluster...")
    try:
        subprocess.run(cmd, check=True)
        print(f"✅ Successfully deleted {node_name}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to delete {node_name}: {e}")
        return False

def stop_k3s_on_node(node_ip, dry_run=False):
    """Stop k3s service on the removed node"""
    ssh_key = Path.home() / ".ssh" / "nuc_homelab_id_ed25519"
    
    commands = [
        "sudo systemctl stop k3s-agent",
        "sudo systemctl disable k3s-agent", 
        "sudo rm -f /etc/rancher/k3s/agent-token"
    ]
    
    for cmd in commands:
        ssh_cmd = [
            'ssh', '-i', str(ssh_key), '-o', 'ConnectTimeout=10', 
            '-o', 'StrictHostKeyChecking=no', f'satya@{node_ip}', cmd
        ]
        
        if dry_run:
            print(f"[DRY RUN] Would run on {node_ip}: {cmd}")
            continue
            
        print(f"🔧 Running on {node_ip}: {cmd}")
        try:
            subprocess.run(ssh_cmd, check=True, capture_output=True)
            print(f"✅ Success: {cmd}")
        except subprocess.CalledProcessError as e:
            print(f"⚠️  Failed on {node_ip}: {cmd} - {e}")

def get_node_ip(removed_nodes):
    """Try to determine IP addresses of removed nodes"""
    # Simple heuristic: assume sequential IPs starting from 192.168.1.141
    base_ip = "192.168.1."
    ip_mapping = {}
    
    for i, node in enumerate(sorted(removed_nodes), start=1):
        if node.startswith('nuc'):
            try:
                node_num = int(node[3:])  # Extract number from nucX
                ip_mapping[node] = f"{base_ip}{140 + node_num}"
            except (ValueError, IndexError):
                print(f"⚠️  Cannot determine IP for {node}")
    
    return ip_mapping

def main():
    parser = argparse.ArgumentParser(description='Cleanup removed k3s nodes')
    parser.add_argument('--dry-run', action='store_true', 
                       help='Show what would be done without making changes')
    args = parser.parse_args()

    print("🧹 k3s Node Cleanup Tool")
    print("=" * 40)
    
    # Load expected nodes from config
    try:
        config = load_cluster_config()
        expected_nodes = {node['name'] for node in config['nodes']}
        print(f"📋 Expected nodes: {sorted(expected_nodes)}")
    except Exception as e:
        print(f"❌ Failed to load cluster.json: {e}")
        sys.exit(1)
    
    # Get actual nodes from k3s
    actual_nodes = get_k3s_nodes()
    if not actual_nodes:
        print("⚠️  No k3s nodes found or kubectl not accessible")
        sys.exit(1)
    
    print(f"🔍 Actual nodes in cluster: {sorted(actual_nodes)}")
    
    # Find nodes to remove
    nodes_to_remove = actual_nodes - expected_nodes
    
    if not nodes_to_remove:
        print("✅ All cluster nodes match configuration. Nothing to clean up!")
        return
    
    print(f"\n🎯 Nodes to remove: {sorted(nodes_to_remove)}")
    
    # Get IP addresses for removed nodes
    node_ips = get_node_ip(nodes_to_remove)
    
    # Show detailed cleanup plan
    print("\n📋 Cleanup Plan:")
    for node_name in sorted(nodes_to_remove):
        node_ip = node_ips.get(node_name, "IP unknown")
        print(f"  🗑️  {node_name} ({node_ip}):")
        print("      1. Drain workloads from node")
        print("      2. Delete node from k3s cluster")
        print(f"     3. Stop k3s services on {node_ip}")
        print("      4. Remove k3s token file")
    
    if args.dry_run:
        print("\n🔍 DRY RUN MODE - No changes will be made")
    else:
        print(f"\n⚠️  This will permanently remove {len(nodes_to_remove)} node(s) from your k3s cluster!")
        print("   - All workloads will be drained and moved to other nodes")
        print("   - Nodes will be deleted from the cluster")
        print("   - k3s services will be stopped on removed nodes")
        response = input("\n🤔 Proceed with cleanup? (y/N): ")
        if response.lower() != 'y':
            print("❌ Cleanup cancelled by user")
            return
    
    # Process each node
    for node_name in sorted(nodes_to_remove):
        print(f"\n🔧 Processing {node_name}...")
        
        # 1. Drain the node
        if not drain_node(node_name, args.dry_run):
            print(f"⚠️  Continuing with {node_name} despite drain failure...")
        
        # 2. Delete from cluster
        if not delete_node(node_name, args.dry_run):
            print(f"⚠️  Continuing with {node_name} despite delete failure...")
        
        # 3. Stop k3s on the node itself
        if node_name in node_ips:
            node_ip = node_ips[node_name]
            print(f"🔌 Stopping k3s on {node_name} ({node_ip})...")
            stop_k3s_on_node(node_ip, args.dry_run)
        else:
            print(f"⚠️  Cannot determine IP for {node_name}, skipping service stop")
    
    if not args.dry_run:
        print(f"\n🎉 Successfully cleaned up {len(nodes_to_remove)} nodes!")
    else:
        print(f"\n🔍 DRY RUN: Would clean up {len(nodes_to_remove)} nodes")
    
    print("\n📝 Next steps:")
    print("1. Verify cluster state: kubectl get nodes")
    print("2. Check workload distribution: kubectl get pods -A -o wide")

if __name__ == "__main__":
    main() 