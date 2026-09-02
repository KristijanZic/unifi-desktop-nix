{
  config,
  lib,
  pkgs,
  ...
}:

# UniFi Identity Enterprise ("UID Enterprise.app", formerly "Identity Enterprise.app").
#
# The app is installed natively into "/Applications/Nix Apps" via
# `environment.systemPackages` and `system.build.applications`.
# The bundled packet-tunnel system extension is supported by macOS sysextd
# from any subdirectory of /Applications, and the privileged helper's
# SMAuthorizedClients requirement matches Ubiquiti's untouched Developer ID signature.
#
# The helper's launchd plist is managed here rather than via
# launchd.daemons because nix-darwin's serviceConfig type cannot express
# SMAuthorizedClients. The plist is the vendor's own, shipped verbatim, and
# is installed and bootstrapped on activation.

let
  cfg = config.services.unifi-identity-enterprise;
  appName = "UID Enterprise.app";
  bundleId = "com.ui.uid.desktop";
  helper = "com.ui.uid.desktop.privilegedtool";
  helperSrc = "${pkgs.unifi-identity-enterprise}/Applications/${appName}/Contents/XPCServices/UIAgentXPC.xpc/Contents/Library/LaunchServices/${helper}";
  helperDst = "/Library/PrivilegedHelperTools/${helper}";
  plist = ./com.ui.uid.desktop.privilegedtool.plist;
  plistDst = "/Library/LaunchDaemons/${helper}.plist";
in
{
  options.services.unifi-identity-enterprise.enable =
    lib.mkEnableOption "UniFi Identity Enterprise app and privileged helper";

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ pkgs.unifi-identity-enterprise ];

      system.activationScripts.postActivation.text = ''
        # Clean up legacy manual installation in /Applications if present
        rm -rf "/Applications/${appName}" "/Applications/Identity Enterprise.app" /var/db/unifi-identity-enterprise-store-path

        mkdir -p /Library/PrivilegedHelperTools
        chmod 755 /Library/PrivilegedHelperTools

        # Install/update the privileged helper binary from the Nix store
        if [ ! -f "${helperDst}" ] || ! cmp -s "${helperSrc}" "${helperDst}"; then
          echo "Installing privileged helper ${helper}"
          cp -f "${helperSrc}" "${helperDst}"
          chmod 755 "${helperDst}"
          chown root:wheel "${helperDst}"
          launchctl kickstart -k "system/${helper}" 2>/dev/null || true
        fi

        # Install/update the vendor launchd plist only when its contents change
        if ! cmp -s "${plist}" "${plistDst}"; then
          echo "Installing launchd daemon ${helper}"
          launchctl bootout "system/${helper}" 2>/dev/null || true
          cp -f "${plist}" "${plistDst}"
          chmod 644 "${plistDst}"
          chown root:wheel "${plistDst}"
          launchctl bootstrap system "${plistDst}"
        elif ! launchctl print "system/${helper}" >/dev/null 2>&1; then
          launchctl bootstrap system "${plistDst}" 2>/dev/null || true
        fi
      '';
    })

    (lib.mkIf (!cfg.enable) {
      system.activationScripts.postActivation.text = ''
        # If disabled, quit app, unload and remove privileged helper daemon
        osascript -e 'quit app "UID Enterprise"' 2>/dev/null || true
        osascript -e 'quit app "Identity Enterprise"' 2>/dev/null || true

        if [ -f "${plistDst}" ]; then
          echo "Removing launchd daemon ${helper} (service disabled)"
          launchctl bootout "system/${helper}" 2>/dev/null || true
          rm -f "${plistDst}"
        fi

        rm -f "${helperDst}"
        rm -rf "/Applications/${appName}" "/Applications/Identity Enterprise.app" /var/db/unifi-identity-enterprise-store-path
      '';
    })
  ];
}
