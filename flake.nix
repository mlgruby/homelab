{
  description = "HomeLab NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, nixpkgs, deploy-rs }: {
    nixosConfigurations = {
      nuc1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nuc1/configuration.nix
        ];
      };
      nuc2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nuc2/configuration.nix
        ];
      };
      nuc3 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nuc3/configuration.nix
        ];
      };
    };

    deploy.nodes = {
      nuc1 = {
        hostname = "192.168.1.141";
        sshUser = "satya";
        user = "root";
        profiles.system = {
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nuc1;
        };
      };
      nuc2 = {
        hostname = "192.168.1.142";
        sshUser = "satya";
        user = "root";
        profiles.system = {
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nuc2;
        };
      };
      nuc3 = {
        hostname = "192.168.1.143";
        sshUser = "satya";
        user = "root";
        profiles.system = {
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nuc3;
        };
      };
    };
    
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  };
}