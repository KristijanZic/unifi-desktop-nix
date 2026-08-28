{
  config,
  lib,
  pkgs,
  ...
}:

# Why not nix-darwin's built-in app setup (system.build.applications)?
# It rsyncs store apps into "/Applications/Nix Apps" with --delete and
# --chmod=-w on every activation. The daemon binary (wifiman-desktopd) expects
# its canonical host app at /Applications/WiFiman Desktop.app (exiting otherwise).
# We copy the apps to /Applications ourselves, keeping them 100% byte-identical
# to the notarized upstream bundles.
#
# By default, wifiman-desktopd writes service.json and wifiman-desktop.log to its
# executable folder (Contents/Resources), which violates Apple Developer ID sealed
# resources and triggers Gatekeeper damage alerts. We configure BASE to point to
# /var/lib/wifiman-desktop and symlink static tools from the app bundle, keeping
# the application bundle untouched and preserving daemon state across rebuilds.

let
  cfg = config.services.wifiman-desktop;
  appName = "WiFiman Desktop.app";
  appPath = "/Applications/${appName}";
  stampPath = "/var/db/wifiman-desktop-nix-store-path";
  dataDir = "/var/lib/wifiman-desktop";
  app = "${pkgs.wifiman-desktop}/Applications/${appName}";
in
{
  options.services.wifiman-desktop.enable = lib.mkEnableOption "WiFiman Desktop app and daemon";

  config = lib.mkIf cfg.enable {
    # Declarative replacement for `wifiman-desktopd install`
    # (kardianos/service: render plist + launchctl load)
    launchd.daemons.wifiman-desktop = {
      serviceConfig = {
        Label = "wifiman-desktop";
        ProgramArguments = [ "${appPath}/Contents/Resources/wifiman-desktopd" ];
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

    system.activationScripts.postActivation.text = ''
      mkdir -p /usr/local/var/log
      mkdir -p "${dataDir}"
      chmod 755 "${dataDir}"

      # Truncate runaway log if it grew excessively
      if [ -f "${dataDir}/wifiman-desktop.log" ]; then
        if [ "$(stat -f%z "${dataDir}/wifiman-desktop.log" 2>/dev/null || echo 0)" -gt 10485760 ]; then
          : > "${dataDir}/wifiman-desktop.log"
        fi
      fi

      # Migrate legacy state from inside the app bundle if present
      if [ -f "${appPath}/Contents/Resources/service.json" ] && [ ! -f "${dataDir}/service.json" ]; then
        cp -p "${appPath}/Contents/Resources/service.json" "${dataDir}/service.json"
      fi

      # Skip app copying if this exact store build is already installed and present
      if [ -d "${appPath}" ] && [ -f "${stampPath}" ] && [ "$(cat "${stampPath}")" = "${app}" ]; then
        true
      else
        echo "Installing ${appName} to /Applications"

        # Quit a running GUI so it doesn't keep running the old version
        osascript -e 'quit app "${appName}"' 2>/dev/null || true

        rm -rf "${appPath}" "/Applications/WiFiman Companion.app"
        cp -R "${app}" "${appPath}"
        xattr -dr com.apple.quarantine "${appPath}" 2>/dev/null || true

        echo "${app}" > "${stampPath}"
      fi

      # Symlink static resources (including hidden .env files) needed by the daemon into BASE
      for item in "${appPath}/Contents/Resources"/* "${appPath}/Contents/Resources"/.[!.]*; do
        [ -e "$item" ] || continue
        fname="$(basename "$item")"
        if [ "$fname" != "wifiman-desktopd" ] && [ "$fname" != "service.json" ] && [ "$fname" != "wifiman-desktop.log" ] && [ "$fname" != "WiFiman Companion.app" ]; then
          ln -sfn "$item" "${dataDir}/$fname"
        fi
      done

      # Restart daemon with updated environment and symlinks.
      # Using 'launchctl kill SIGTERM' tells launchd to gracefully cycle the process;
      # launchd's KeepAlive will immediately restart it with the updated binary/resources
      # without blocking activation if launchd throttles rapid spawns.
      launchctl kill SIGTERM system/wifiman-desktop 2>/dev/null \
        || launchctl kickstart system/wifiman-desktop 2>/dev/null \
        || true
    '';
  };
}
