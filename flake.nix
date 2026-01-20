{
  description = "Hytale Launcher - Official launcher for Hytale game";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" ];
      eachSystem = lib.genAttrs systems;
      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          localSystem.system = system;
          config.allowUnfree = true;
        }
      );
    in
    {
      packages = eachSystem (system: {
        default = self.packages.${system}.hytale-launcher;
        inherit (pkgsFor.${system}.callPackage ./package.nix { })
          hytale-launcher
          hytale-launcher-unwrapped
          ;
      });

      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.hytale-launcher}/bin/hytale-launcher";
        };
      });

    };
}
