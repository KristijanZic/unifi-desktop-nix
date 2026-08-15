{
  config,
  lib,
  pkgs,
  ...
}:

# Why not nix-darwin's built-in app setup (system.build.applications)?
# It rsyncs store apps into "/Applications/Nix Apps" with --delete and
# --chmod=-w on every activation, which would wipe the daemon's runtime state
# (service.json, wifiman-desktop.log — written into Contents/Resources) on
# every rebuild. Wrapping can't help (the daemon locates its data dir via its
# own executable path, kardianos/osext) and patching is a dead end (runtime-
# derived path, Developer ID + TCC identity loss). We therefore copy the app
# to the vendor's canonical path ourselves, preserving service.json.

let
  cfg = config.services.wifiman-desktop;
  appName = "WiFiman Desktop.app";
  appPath = "/Applications/${appName}";
  stampPath = "/var/db/wifiman-desktop-nix-store-path";
  app = "${pkgs.wifiman-desktop}/Applications/${appName}";
in
{
  options.services.wifiman-desktop.enable =
    lib.mkEnableOption "WiFiman Desktop app and daemon";

  config = lib.mkIf cfg.enable {
    # Declarative replacement for `wifiman-desktopd install`
    # (kardianos/service: render plist + launchctl load)
    launchd.daemons.wifiman-desktop = {
      serviceConfig = {
        Label = "wifiman-desktop";
        ProgramArguments = [ "${appPath}/Contents/Resources/wifiman-desktopd" ];
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

      # Skip if this exact store build is already installed
      if [ -f "${stampPath}" ] && [ "$(cat "${stampPath}")" = "${app}" ]; then
        true
      else
        echo "Installing ${appName} to /Applications"

        # Quit a running GUI so it doesn't keep running the old version
        osascript -e 'quit app "${appName}"' 2>/dev/null || true

        # Preserve daemon state across rebuilds, like the official installer does
        if [ -f "${appPath}/Contents/Resources/service.json" ]; then
          cp "${appPath}/Contents/Resources/service.json" /tmp/.wifiman-desktop-service.json
        fi

        rm -rf "${appPath}"
        cp -R "${app}" "${appPath}"
        chmod -R u+w "${appPath}"

        if [ -f /tmp/.wifiman-desktop-service.json ]; then
          mv /tmp/.wifiman-desktop-service.json "${appPath}/Contents/Resources/service.json"
        fi

        echo "${app}" > "${stampPath}"

        # The daemon binary was replaced under a stable path, so the plist
        # didn't change and nix-darwin won't restart it on its own
        launchctl kickstart -k system/wifiman-desktop 2>/dev/null || true
      fi
    '';
  };
}
