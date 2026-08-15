{
  description = "Ubiquiti desktop apps for macOS (WiFiman Desktop, UniFi Identity)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-darwin"
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
        in
        nixpkgs.lib.genAttrs packageNames (name: pkgs.callPackage ./packages/${name}/package.nix { })
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
    };
}
