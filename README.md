# ubiquiti-apps

Nix packages and nix-darwin modules for Ubiquiti's macOS desktop apps:

| Package | App | Bundle ID |
|---|---|---|
| `wifiman-desktop` | WiFiman Desktop 1.2.8 | `ui.wifiman.desktop` |
| `unifi-identity-endpoint` | UniFi Endpoint 4.1.1 | `com.ui.uid.standard-desktop` |
| `unifi-identity-enterprise` | UID Enterprise 0.90.0 | `com.ui.uid.desktop` |

All apps are unfree, notarized Developer ID binaries fetched from Ubiquiti's
official download endpoints and installed byte-identical (their privileged
helpers and system extensions are pinned to Ubiquiti's code signature, so
modification or re-signing is impossible by design).

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    ubiquiti-apps.url = "github:<you>/ubiquiti-apps";
  };

  outputs = { nix-darwin, ubiquiti-apps, ... }: {
    darwinConfigurations.yourHost = nix-darwin.lib.darwinSystem {
      modules = [
        # import only what you use:
        ubiquiti-apps.darwinModules.wifiman-desktop
        ubiquiti-apps.darwinModules.unifi-identity-endpoint
        # ubiquiti-apps.darwinModules.unifi-identity-enterprise
        # (or all of them: ubiquiti-apps.darwinModules.default)

        ({ lib, ... }: {
          nixpkgs.config.allowUnfreePredicate = pkg:
            builtins.elem (lib.getName pkg) [
              "wifiman-desktop"
              "unifi-identity-endpoint"
              "unifi-identity-enterprise"
            ];
        })
      ];
    };
  };
}
```

Each module applies this flake's overlay itself, so `pkgs.<name>` resolves
without extra wiring.

## What the modules do

All modules install the app to its vendor-canonical path in `/Applications`
via an idempotent (stamp-file-guarded) activation script, because:

- nix-darwin's built-in app setup rsyncs into `/Applications/Nix Apps` with
  `--delete` and `--chmod=-w` on every activation — incompatible with apps
  that keep runtime state in their bundle (WiFiman's `service.json`) or that
  must live in `/Applications` (system extension hosts)
- upgrades mirror the vendor pkg scripts: quit the app, remove legacy app
  names, replace the bundle, preserve state where the vendor does
- daemons/helpers are declared via `launchd.daemons` with plist contents
  identical to the vendor-generated ones, so nix-darwin manages their
  lifecycle (and removal when you drop the module)

## Caveats

- **First launch of the Identity apps requires approving the network system
  extension** in System Settings (and a login item for Enterprise). This
  cannot be automated without MDM.
- The Identity download URLs are unversioned (`download.uid.ui.com/?app=…`)
  and always serve the latest release. The pinned hash therefore fails on
  upstream updates — this is deliberate; bump `version` + `hash` together
  (`nix store prefetch-file <url>`).
- Apps are intentionally **not** added to `environment.system-packages`; use
  the darwin modules only.
- Removing a module unloads its launchd daemons, but the copied app in
  `/Applications` is left behind (same gap as the vendor's own uninstaller,
  which Homebrew also only approximates).

## Upstreaming to nixpkgs

Each `packages/<name>/package.nix` is a self-contained drop-in for
`pkgs/by-name/<first-two-letters>/<name>/package.nix`. Add yourself to
`meta.maintainers` and `maintainers/maintainer-list.nix` before opening a PR.

## Adding a new app

1. `mkdir packages/<name>` and write `package.nix` (copy an existing one)
2. If it needs daemons/helpers or a canonical `/Applications` path, add
   `modules/nix-darwin/<name>.nix` (copy an existing one)
3. Add `<name>` to `packageNames` in `flake.nix`
