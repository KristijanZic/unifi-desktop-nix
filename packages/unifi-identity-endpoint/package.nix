{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  cpio,
  writeShellApplication,
  curl,
  gnused,
  common-updater-scripts,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "unifi-identity-endpoint";
  version = "4.1.1";

  src = fetchurl {
    name = "${finalAttrs.pname}-${finalAttrs.version}.pkg";
    url = "https://fw-download.ubnt.com/data/uid-identity-standard-desktop-app/b56c-macOS-4.1.1-8b02ea8c-a9bc-4fc4-a6ae-56f968c94385.pkg";
    hash = "sha256-sutdWoamgGd382w9ssDFY8g3NVnmRZvo9TTjpu2fGtM=";
  };

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [
    xar
    cpio
  ];

  unpackPhase = ''
    runHook preUnpack

    # xar recursively expands the component pkg as well,
    # leaving us with UniFi_Endpoint.pkg/Payload
    xar -xf "$src"

    mkdir app && (cd app && gzip -dc < ../UniFi_Endpoint.pkg/Payload | cpio -i)

    # The payload may store code-signature xattrs as AppleDouble (._) files;
    # the macOS installer restores them as xattrs, GNU cpio cannot, so drop them
    find app -name '._*' -delete

    sourceRoot=app
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -R "Applications/UniFi Endpoint.app" "$out/Applications/"

    runHook postInstall
  '';

  passthru.updateScript = lib.getExe (writeShellApplication {
    name = "update-unifi-identity-endpoint";
    runtimeInputs = [
      curl
      gnused
      common-updater-scripts
    ];
    text = ''
      download_url="https://download.uid.ui.com/?app=DESKTOP-IDENTITY-STANDARD-MACOS"

      final_url="$(curl --fail --silent --show-error --location --output /dev/null --write-out '%{url_effective}' "$download_url")"

      new_version="$(printf '%s\n' "$final_url" | sed -nE 's#^.*macOS-([0-9]+(\.[0-9]+)*)-[^/]+\.pkg$#\1#p')"

      if [[ -z "$new_version" ]]; then
        echo "Unable to determine the version from:"
        echo "$final_url"
        exit 1
      fi

      if [[ "${finalAttrs.version}" == "$new_version" ]]; then
        echo "The new version is the same as the old version."
        exit 0
      fi

      update-source-version "${finalAttrs.pname}" "$new_version" "" "$final_url" --ignore-same-version
    '';
  });

  meta = {
    description = "UniFi Identity Endpoint — one-click WiFi, VPN and door access (Ubiquiti)";
    longDescription = ''
      UniFi Identity Endpoint is Ubiquiti's client application for site-managed UniFi
      consoles (such as Dream Machines and Cloud Gateways), enabling frictionless local
      and remote resource access for users.

      Key features include:
      - One-Click Wi-Fi connection to corporate networks without typing passwords.
      - One-Click VPN for secure, encrypted remote access to local subnets.
      - Door access integration and digital credential authorization via UniFi Access.
      - Softphone features with UniFi Talk integration for taking workspace calls on desktop.
    '';
    homepage = "https://ui.com/identity";
    downloadPage = "https://ui.com/download/app/identity-desktop";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = lib.platforms.darwin;
    identifiers = {
      cpeParts = {
        part = "a";
        vendor = "ui";
        product = "unifi_identity_endpoint";
        version = finalAttrs.version;
        target_sw = "macos";
      };
      purlParts = {
        type = "generic";
        spec = "ubiquiti/unifi-identity-endpoint@${finalAttrs.version}";
      };
    };
    maintainers = with lib.maintainers; [ KristijanZic ];
  };
})
