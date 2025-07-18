{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../common/common.nix
    ../../common/k3s-cluster.nix  # Import k3s cluster settings
    ../../common/deploy-rs.nix    # Import deploy-rs specific settings
  ];

  networking.hostName = "nuc1";

  # k3s server configuration (control plane)
  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = toString [
      "--data-dir=/data/k3s"
      "--default-local-storage-path=/data/k8s-volumes"
      "--disable=traefik"
      "--flannel-backend=vxlan"
    ];
  };

  # Open k3s ports in firewall
  networking.firewall = {
    allowedTCPPorts = [
      6443 # Kubernetes API server
      10250 # Kubelet metrics
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
    ];
  };

  system.stateVersion = "24.05";
}