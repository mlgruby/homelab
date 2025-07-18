{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../common/common.nix
  ];

  networking.hostName = "nuc3";

  # k3s agent configuration (worker node)
  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://192.168.1.141:6443"; # Point to nuc1 (server)
    tokenFile = "/etc/rancher/k3s/agent-token"; # Token file for authentication
    extraFlags = toString [
      "--data-dir=/data/k3s" # Use NVMe for k3s data
      "--default-local-storage-path=/data/k8s-volumes" # Use NVMe for local storage
    ];
  };

  # Open k3s ports in firewall
  networking.firewall = {
    allowedTCPPorts = [
      10250 # Kubelet metrics
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
    ];
  };

  system.stateVersion = "24.05";
}
