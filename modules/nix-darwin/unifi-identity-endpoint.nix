{ pkgs, ... }:

# UniFi Identity Endpoint ("UniFi Endpoint.app", formerly "Identity.app").
#
# The app is copied to its vendor-canonical path because it bundles a
# packet-tunnel system extension (activation requires the app in
# /Applications) and a privileged helper whose SMAuthorizedClients requirement
# pins the XPC agent to Ubiquiti's Developer ID signature — so the bundle must
# stay byte-identical. Unlike nix-darwin's "Nix Apps" rsync (--delete,
# --chmod=-w), this copy is idempotent via a stamp file and upgrades mirror
# the vendor's pre/postinstall scripts (quit app, remove legacy name, replace,
# reinstall helper). The system extension itself is activated by the app on
# first launch and approved by the user in System Settings; nothing here can
# or should automate that.
#
# The helper's launchd plist is managed here rather than via
# launchd.daemons because nix-darwin's serviceConfig type cannot express
# SMAuthorizedClients. The plist is the vendor's own, shipped verbatim, and
# is only replaced/bootstrapped when its contents change.

let
  appName = "UniFi Endpoint.app";
  appPath = "/Applications/${appName}";
  legacyAppPath = "/Applications/Identity.app";
  stampPath = "/var/db/unifi-identity-endpoint-store-path";
  bundleId = "com.ui.uid.standard-desktop";
  helper = "com.ui.uid.standard-desktop.privilegedtool";
  helperSrc = "${appPath}/Contents/XPCServices/${bundleId}.agent.xpc/Contents/Library/LaunchServices/${helper}";
  helperDst = "/Library/PrivilegedHelperTools/${helper}";
  plist = ./com.ui.uid.standard-desktop.privilegedtool.plist;
  plistDst = "/Library/LaunchDaemons/${helper}.plist";
  app = "${pkgs.unifi-identity-endpoint}/Applications/${appName}";
in
{
  system.activationScripts.postActivation.text = ''
    mkdir -p -m 755 /Library/PrivilegedHelperTools

    # Skip if this exact store build is already installed
    if [ -f "${stampPath}" ] && [ "$(cat "${stampPath}")" = "${app}" ]; then
      true
    else
      echo "Installing ${appName} to /Applications"

      # Quit a running app, like the vendor preinstall does
      osascript -e 'quit app "UniFi Endpoint"' 2>/dev/null || true
      osascript -e 'quit app "Identity"' 2>/dev/null || true

      # Remove the legacy-named app if it is the same product
      if [ -f "${legacyAppPath}/Contents/Info.plist" ] \
        && [ "$(/usr/libexec/PlistBuddy -c 'print :CFBundleIdentifier' "${legacyAppPath}/Contents/Info.plist" 2>/dev/null)" = "${bundleId}" ]; then
        rm -rf "${legacyAppPath}"
      fi

      rm -rf "${appPath}"
      cp -R "${app}" "${appPath}"
      chmod -R u+w "${appPath}"

      # Replace the privileged helper with the new build's copy
      rm -f "${helperDst}"
      cp -f "${helperSrc}" "${helperDst}"
      chmod 755 "${helperDst}"
      chown root:wheel "${helperDst}"

      echo "${app}" > "${stampPath}"

      # The helper binary was replaced under a stable path; restart it if loaded
      launchctl kickstart -k "system/${helper}" 2>/dev/null || true
    fi

    # Install/update the vendor plist only when its contents change
    if ! cmp -s "${plist}" "${plistDst}"; then
      echo "Installing launchd daemon ${helper}"
      launchctl bootout "system/${helper}" 2>/dev/null || true
      cp -f "${plist}" "${plistDst}"
      chmod 644 "${plistDst}"
      chown root:wheel "${plistDst}"
      launchctl bootstrap system "${plistDst}"
    fi
  '';
}
