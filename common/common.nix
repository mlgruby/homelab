{ config, pkgs, ... }:

{
  imports = [ ];

  # Basic system settings
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.useDHCP = true;
  networking.firewall.enable = false; # Disable for k3s cluster communication

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.PermitRootLogin = "yes"; # Required for deploy-rs

  # Define your user account.
  users.users.satya = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable 'sudo'
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEomtxD4A137gFGJG0cMXMidR5wQymAiay5vUS89qkX8 nuc-homelab-key"
    ];
  };

  # Allow root SSH access for deploy-rs (with same key)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEomtxD4A137gFGJG0cMXMidR5wQymAiay5vUS89qkX8 nuc-homelab-key"
  ];

  # Ensure data directories exist
  systemd.tmpfiles.rules = [
    "d /data/k3s 0755 root root -"
    "d /data/k8s-volumes 0755 root root -"
  ];

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    iptables
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
