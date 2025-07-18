{ config, pkgs, ... }:

{
  imports = [
    ../../common/common.nix
  ];

  networking.hostName = "nuc1";
  system.stateVersion = "24.05";
}
