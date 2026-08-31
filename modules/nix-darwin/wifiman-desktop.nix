{
  config,
  lib,
  pkgs,
  ...
}:

# Why not install exclusively to /Applications?
# Nix-darwin provides a native application management mechanism via
# `environment.systemPackages` and `system.build.applications`, which rsyncs
# apps into "/Applications/Nix Apps" with --delete and --chmod=-w.
# By delegating to nix-darwin's native app setup:
#   1. Apps are automatically placed in "/Applications/Nix Apps".
#   2. Apps are automatically removed by nix-darwin when disabled or unimported.
#   3. Activation is fast because nix-darwin doesn't need custom cp -R logic.
#
# However, wifiman-desktopd hardcodes a check:
#   os.Stat("/Applications/WiFiman Desktop.app")
# exiting/uninstalling if not found. We satisfy this check with a lightweight
# symlink at /Applications/WiFiman Desktop.app -> /Applications/Nix Apps/WiFiman Desktop.app.
#
# By default, wifiman-desktopd writes service.json and wifiman-desktop.log to its
# executable folder (Contents/Resources). We configure BASE to point to
# /var/lib/wifiman-desktop and symlink static tools from the app bundle, keeping
# the application bundle untouched and preserving daemon state across rebuilds.

let
  cfg = config.services.wifiman-desktop;
  appName = "WiFiman Desktop.app";
  nixAppPath = "/Applications/Nix Apps/${appName}";
  compatSymlink = "/Applications/${appName}";
  dataDir = "/var/lib/wifiman-desktop";
in
{
  options.services.wifiman-desktop.enable = lib.mkEnableOption "WiFiman Desktop app and daemon";

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # Adds the app to system.build.applications so nix-darwin automatically
      # installs, updates, and deletes it in /Applications/Nix Apps natively
      environment.systemPackages = [ pkgs.wifiman-desktop ];

      # Declarative replacement for `wifiman-desktopd install`
      launchd.daemons.wifiman-desktop = {
        serviceConfig = {
          Label = "wifiman-desktop";
          ProgramArguments = [ "${nixAppPath}/Contents/Resources/wifiman-desktopd" ];
          EnvironmentVariables = {
            BASE = dataDir;
          };
          RunAtLoad = true;
          KeepAlive = true;
          SessionCreate = false;
          StandardOutPath = "/usr/local/var/log/wifiman-desktop.out.log";
          StandardErrorPath = "/usr/local/var/log/wifiman-desktop.err.log";
        };
      };

      # Runs before nix-darwin's launchd setup, so the legacy vendor plist
      # (same label) is gone before our daemon is bootstrapped
      system.activationScripts.preActivation.text = ''
        if [ -f /Library/LaunchDaemons/wifiman-desktop.plist ]; then
          echo "Removing legacy vendor-installed wifiman-desktop daemon"
          launchctl bootout system/wifiman-desktop 2>/dev/null \
            || launchctl unload /Library/LaunchDaemons/wifiman-desktop.plist 2>/dev/null \
            || true
          rm -f /Library/LaunchDaemons/wifiman-desktop.plist
        fi
      '';

      # Runs right after nix-darwin's applications rsync, before launchd services start
      system.activationScripts.extraActivation.text = ''
        # Remove any legacy full copy if it exists from previous versions
        if [ -d "${compatSymlink}" ] && [ ! -L "${compatSymlink}" ]; then
          rm -rf "${compatSymlink}"
        fi
        rm -rf "/Applications/WiFiman Companion.app" /var/db/wifiman-desktop-nix-store-path

        # Create compatibility symlink in /Applications so the daemon's
        # internal checkIfAppInstalled (os.Stat("/Applications/WiFiman Desktop.app")) passes
        ln -sfn "${nixAppPath}" "${compatSymlink}"
      '';

      system.activationScripts.postActivation.text = ''
        mkdir -p /usr/local/var/log
        mkdir -p "${dataDir}"
        chmod 755 "${dataDir}"

        # Ensure compatibility symlink exists
        ln -sfn "${nixAppPath}" "${compatSymlink}"

        # Truncate runaway log if it grew excessively
        if [ -f "${dataDir}/wifiman-desktop.log" ]; then
          if [ "$(stat -f%z "${dataDir}/wifiman-desktop.log" 2>/dev/null || echo 0)" -gt 10485760 ]; then
            : > "${dataDir}/wifiman-desktop.log"
          fi
        fi

        # Migrate legacy state from inside the app bundle if present
        if [ -f "${nixAppPath}/Contents/Resources/service.json" ] && [ ! -f "${dataDir}/service.json" ]; then
          cp -p "${nixAppPath}/Contents/Resources/service.json" "${dataDir}/service.json"
        fi

        # Symlink static resources (including hidden .env files) needed by the daemon into BASE
        for item in "${nixAppPath}/Contents/Resources"/* "${nixAppPath}/Contents/Resources"/.[!.]*; do
          [ -e "$item" ] || continue
          fname="$(basename "$item")"
          if [ "$fname" != "wifiman-desktopd" ] && [ "$fname" != "service.json" ] && [ "$fname" != "wifiman-desktop.log" ] && [ "$fname" != "WiFiman Companion.app" ]; then
            ln -sfn "$item" "${dataDir}/$fname"
          fi
        done

        # Ensure the daemon is loaded and running
        launchctl bootstrap system /Library/LaunchDaemons/wifiman-desktop.plist 2>/dev/null \
          || launchctl load -w /Library/LaunchDaemons/wifiman-desktop.plist 2>/dev/null \
          || launchctl kill SIGTERM system/wifiman-desktop 2>/dev/null \
          || launchctl kickstart system/wifiman-desktop 2>/dev/null \
          || true
      '';
    })

    (lib.mkIf (!cfg.enable) {
      system.activationScripts.postActivation.text = ''
        # Quit running GUI if open
        osascript -e 'quit app "${appName}"' 2>/dev/null || true

        # Stop and remove launchd daemon if still loaded
        launchctl bootout system/wifiman-desktop 2>/dev/null \
          || launchctl unload /Library/LaunchDaemons/wifiman-desktop.plist 2>/dev/null \
          || true
        rm -f /Library/LaunchDaemons/wifiman-desktop.plist

        # Clean up compatibility symlink or legacy copy in /Applications
        if [ -L "${compatSymlink}" ] || [ -d "${compatSymlink}" ]; then
          echo "Removing ${compatSymlink} (service disabled)"
          rm -rf "${compatSymlink}"
        fi
        rm -rf "/Applications/WiFiman Companion.app" /var/db/wifiman-desktop-nix-store-path

        # Clean up static resource symlinks in dataDir
        if [ -d "${dataDir}" ]; then
          for item in "${dataDir}"/* "${dataDir}"/.[!.]*; do
            [ -L "$item" ] && rm -f "$item"
          done
        fi

        # Truncate runaway log if it grew excessively
        if [ -f "${dataDir}/wifiman-desktop.log" ]; then
          if [ "$(stat -f%z "${dataDir}/wifiman-desktop.log" 2>/dev/null || echo 0)" -gt 10485760 ]; then
            : > "${dataDir}/wifiman-desktop.log"
          fi
        fi
      '';
    })
  ];
}
