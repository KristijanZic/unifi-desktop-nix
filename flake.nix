{
  description = "Ubiquiti desktop apps for macOS and Linux (WiFiman Desktop, UniFi Identity)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-linux"
        # x86_64-darwin is dropped in nixpkgs 26.11 (its dependency tree no
        # longer evaluates there); Intel Mac builds remain possible via the
        # overlay against nixpkgs 26.05
      ];

      packageNames = [
        "wifiman-desktop"
        "unifi-identity-endpoint"
        "unifi-identity-enterprise"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          allPackages = nixpkgs.lib.genAttrs packageNames (
            name: pkgs.callPackage ./packages/${name}/package.nix { }
          );
        in
        nixpkgs.lib.filterAttrs (_: pkg: nixpkgs.lib.elem system pkg.meta.platforms) allPackages
      );

      overlays.default =
        final: prev:
        nixpkgs.lib.genAttrs packageNames (name: final.callPackage ./packages/${name}/package.nix { });

      darwinModules =
        nixpkgs.lib.genAttrs packageNames (
          name:
          { ... }:
          {
            imports = [ ./modules/nix-darwin/${name}.nix ];
            nixpkgs.overlays = [ self.overlays.default ];
          }
        )
        // {
          default = {
            imports = builtins.attrValues (nixpkgs.lib.removeAttrs self.darwinModules [ "default" ]);
          };
        };

      nixosModules.wifiman-desktop = {
        imports = [ ./modules/nixos/wifiman-desktop.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };
      nixosModules.default = self.nixosModules.wifiman-desktop;
    };
}
