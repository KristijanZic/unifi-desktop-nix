{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  cpio,
  writeShellApplication,
  curl,
  jq,
  common-updater-scripts,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "wifiman-desktop";
  version = "1.2.8";

  src = finalAttrs.passthru.sources.${system};

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [
    xar
    cpio
  ];

  unpackPhase = ''
    runHook preUnpack

    # xar recursively expands the component pkgs as well,
    # leaving us with {WifimanDesktop,WiFimanNetworkHelper}.pkg/Payload
    xar -xf "$src"

    mkdir app && (cd app && gzip -dc < ../WifimanDesktop.pkg/Payload | cpio -i)
    mkdir companion && (cd companion && gzip -dc < ../WiFimanNetworkHelper.pkg/Payload | cpio -i)

    # The payload stores code-signature xattrs as AppleDouble (._) files;
    # the macOS installer restores them as xattrs, GNU cpio cannot, so drop them
    find app companion -name '._*' -delete

    # Mirror the official postinstall script:
    # nest the companion app inside the main app's Resources
    mv "companion/WiFiman Companion.app" "app/WiFiman Desktop.app/Contents/Resources/"

    sourceRoot=app
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -R "WiFiman Desktop.app" "$out/Applications/"

    runHook postInstall
  '';

  passthru = {
    sources = {
      aarch64-darwin = fetchurl {
        url = "https://desktop.wifiman.com/wifiman-desktop-${finalAttrs.version}-arm64.pkg";
        hash = "sha256-To9RqgISIieoyTupquagqnc4cBoKDiMSSHh8JjGewBE=";
      };

      x86_64-darwin = fetchurl {
        url = "https://desktop.wifiman.com/wifiman-desktop-${finalAttrs.version}-amd64.pkg";
        hash = "sha256-wPkP+Kfs30haFii3AjWjshCDohLhiNprlB5Euk6a//w=";
      };
    };

    updateScript = writeShellApplication {
      name = "update-wifiman-desktop";
      runtimeInputs = [
        curl
        jq
        common-updater-scripts
      ];
      text = ''
        manifest="$(curl --fail --silent --show-error https://desktop.wifiman.com/wifiman-desktop-macos-manifest.json)"

        new_version="$(jq --exit-status --raw-output '.version' <<< "$manifest")"

        if [[ "${finalAttrs.version}" == "$new_version" ]]; then
          echo "The new version is the same as the old version."
          exit 0
        fi

        for platform in ${lib.escapeShellArgs (builtins.attrNames finalAttrs.passthru.sources)}; do
          update-source-version "${finalAttrs.pname}" "$new_version" --ignore-same-version --source-key="sources.$platform"
        done
      '';
    };
  };

  meta = {
    description = "Scan, analyze and optimize nearby wireless networks (Ubiquiti WiFiman Desktop)";
    longDescription = ''
      WiFiman Desktop is a powerful wireless network analysis and optimization tool
      developed by Ubiquiti. Designed for network administrators, IT professionals,
      and enthusiasts, it provides real-time visibility into Wi-Fi network performance
      and environmental coverage.

      Key features include:
      - Continuous Wi-Fi scanning to detect nearby Access Points (APs), signal strength (RSSI),
        and channel utilization.
      - Integrated speed testing and latency monitoring to evaluate local network performance
        and internet connectivity.
      - Detailed device discovery across local subnets to identify connected network clients,
        IP addresses, MAC addresses, and vendor details.
      - Seamless integration with Ubiquiti UniFi network deployments for enhanced telemetry
        and seamless remote connection options (such as Teleport VPN).
    '';
    homepage = "https://wifiman.com/";
    downloadPage = "https://ui.com/download/app/wifiman-desktop";
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    identifiers = {
      cpeParts = {
        part = "a";
        vendor = "ui";
        product = "wifiman_desktop";
        version = finalAttrs.version;
      };
      purlParts = {
        type = "generic";
        spec = "ubiquiti/wifiman-desktop@${finalAttrs.version}";
      };
    };
    maintainers = with lib.maintainers; [ KristijanZic ];
  };
})
