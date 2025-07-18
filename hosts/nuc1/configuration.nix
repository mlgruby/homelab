{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../common/common.nix
  ];

  networking.hostName = "nuc1";

  # k3s server configuration (control plane)
  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true; # Initialize a new cluster using embedded etcd
    extraFlags = toString [
      "--data-dir=/data/k3s" # Use NVMe for k3s data
      "--default-local-storage-path=/data/k8s-volumes" # Use NVMe for local storage
      "--disable=traefik" # We'll configure ingress separately
      "--flannel-backend=vxlan" # Use VXLAN for networking
    ];
  };

  # Open k3s ports in firewall (even though we disabled it globally)
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
