# unifi-desktop-nix

Nix packages and nix-darwin modules for Ubiquiti's macOS desktop apps,
plus a NixOS package and module for WiFiman Desktop on Linux:

| Package | App | Bundle ID | Platforms |
|---|---|---|---|
| `wifiman-desktop` | WiFiman Desktop 1.2.8 | `ui.wifiman.desktop` | macOS (arm64; x86_64 via overlay on nixpkgs 26.05), Linux (x86_64) |
| `unifi-identity-endpoint` | UniFi Endpoint 4.1.1 | `com.ui.uid.standard-desktop` | macOS (arm64; x86_64 via overlay on nixpkgs 26.05) |
| `unifi-identity-enterprise` | UID Enterprise 0.90.0 | `com.ui.uid.desktop` | macOS (arm64; x86_64 via overlay on nixpkgs 26.05) |

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
    unifi-desktop-nix.url = "github:KristijanZic/unifi-desktop-nix";
  };

  outputs = { nix-darwin, unifi-desktop-nix, ... }: {
    darwinConfigurations.yourHost = nix-darwin.lib.darwinSystem {
      modules = [
        # import only what you use:
        unifi-desktop-nix.darwinModules.wifiman-desktop
        unifi-desktop-nix.darwinModules.unifi-identity-endpoint
        # unifi-desktop-nix.darwinModules.unifi-identity-enterprise
        # (or all of them: unifi-desktop-nix.darwinModules.default)

        ({ lib, ... }: {
          # Enable desired services declaratively:
          services.wifiman-desktop.enable = true;
          services.unifi-identity-endpoint.enable = true;
          # services.unifi-identity-enterprise.enable = true;

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

## NixOS (WiFiman Desktop on Linux)

`wifiman-desktop` also packages the vendor's amd64 `.deb` for
`x86_64-linux` (binaries patched with `autoPatchelfHook` against GTK3 /
WebKitGTK 4.1, tray support via `libayatana-appindicator`). Enable the
vendor's root daemon declaratively:

```nix
{
  inputs.unifi-desktop-nix.url = "github:KristijanZic/unifi-desktop-nix";

  outputs = { nixpkgs, unifi-desktop-nix, ... }: {
    nixosConfigurations.yourHost = nixpkgs.lib.nixosSystem {
      modules = [
        unifi-desktop-nix.nixosModules.wifiman-desktop

        ({ lib, ... }: {
          services.wifiman-desktop.enable = true;
          nixpkgs.config.allowUnfreePredicate = pkg:
            builtins.elem (lib.getName pkg) [ "wifiman-desktop" ];
        })
      ];
    };
  };
}
```

The module installs the package, mirrors the vendor's systemd unit
(`wifiman-desktopd`, root, `Restart=always`) with a store-path `ExecStart`,
and puts the deb's runtime `Depends` (`net-tools`, `iw`, `resolvconf`) on
the service's PATH. The patched vendor unit is also shipped at
`$out/lib/systemd/system/` for non-NixOS distros.

## What the modules do

All modules integrate with nix-darwin's native application management:

- Apps are added to `environment.systemPackages` and placed in `/Applications/Nix Apps`
  via nix-darwin's built-in application activation script.
- Disabling a service (`services.<name>.enable = false;`) or removing it from your
  configuration automatically cleans up the app bundle from `/Applications/Nix Apps`,
  unloads and removes launchd daemons, and cleans up privileged helper tools.
- Background daemons and privileged helpers are bootstrapped and managed with their
  vendor plists and permissions (`SMAuthorizedClients` Developer ID validation).
- WiFiman Desktop runtime state is preserved across rebuilds in `/var/lib/wifiman-desktop`.

## Caveats

- **x86_64-darwin is dropped in nixpkgs 26.11** (this flake's `nixpkgs`
  input), so the flake no longer exposes it — its dependency tree doesn't
  evaluate there anymore. The Intel `.pkg` sources remain in the packages;
  use the overlay against `nixpkgs-26.05-darwin` if you still need them.
- **WiFiman on Linux**: the system tray icon requires a StatusNotifier/appindicator-capable
  desktop environment; the daemon needs CAP_NET_ADMIN-ish root (runs as root,
  like the vendor unit) for WireGuard. Tested against the vendor `.deb` layout.
- **First launch of the Identity apps requires approving the network system
  extension** in System Settings (and a login item for Enterprise). This
  cannot be automated without MDM.
- The Identity download URLs are unversioned (`download.uid.ui.com/?app=…`)
  and always serve the latest release. The pinned hash therefore fails on
  upstream updates — this is deliberate; bump `version` + `hash` together
  (`nix store prefetch-file <url>`).
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
