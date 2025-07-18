# k3s cluster specific configuration
# This file contains settings required for k3s cluster operation
# It should only be imported in configurations that are part of the k3s cluster

{ config, pkgs, ... }:

{
  # Disable firewall for k3s cluster communication
  networking.firewall.enable = false;

  # Mount the NVMe data drive (from hardware-configuration.nix labels)
  fileSystems."/data" = {
    device = "/dev/disk/by-label/data";
    fsType = "ext4";
    options = [ "defaults" ];
  };

  # Ensure k3s data directories exist
  systemd.tmpfiles.rules = [
    "d /data/k3s 0755 root root -"
    "d /data/k8s-volumes 0755 root root -"
  ];

  # Additional packages useful for cluster management
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    iptables
  ];
} 