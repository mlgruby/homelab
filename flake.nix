{
  description = "A declarative homelab configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      nuc1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { };
        modules = [ ./hosts/nuc1/configuration.nix ];
      };
      nuc2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { };
        modules = [ ./hosts/nuc2/configuration.nix ];
      };
      nuc3 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { };
        modules = [ ./hosts/nuc3/configuration.nix ];
      };
    };
  };
}
