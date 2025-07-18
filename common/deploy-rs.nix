# deploy-rs specific configuration
# This file contains settings required for deploy-rs automation
# It should only be imported in configurations managed by deploy-rs

{ config, pkgs, ... }:

{
  # Allow root SSH access for deploy-rs (with same key as user)
  users.users.root.openssh.authorizedKeys.keys = config.users.users.satya.openssh.authorizedKeys.keys;

  # Allow passwordless sudo for wheel group (required for deploy-rs)
  security.sudo.wheelNeedsPassword = false;

  # Enable root login for deploy-rs
  services.openssh.settings.PermitRootLogin = "yes";
} 