{ config, pkgs, ... }:

{
  imports = [
    ../../common/common.nix
  ];

  networking.hostName = "nuc2";
  system.stateVersion = "24.05";
}
