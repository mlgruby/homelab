{ config, pkgs, ... }:

{
  imports = [
    ../../common/common.nix
  ];

  networking.hostName = "nuc3";
  system.stateVersion = "24.05";
}
