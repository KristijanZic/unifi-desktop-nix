{
  config,
  lib,
  pkgs,
  ...
}:

# WiFiman Desktop on Linux: the vendor deb ships a root daemon
# (wifiman-desktopd) as a systemd unit and a GTK/WebKitGTK GUI that talks
# to it. We enable the same daemon declaratively instead of installing the
# shipped unit verbatim, so nixos-rebuild restarts it when the store path
# changes. The daemon locates its bundled tools (wg, wireguard-go, wg-quick)
# via its own executable path; nettools/iw/openresolv mirror the deb's
# Depends, which the GUI/daemon shell out to.

let
  cfg = config.services.wifiman-desktop;
in
{
  options.services.wifiman-desktop.enable = lib.mkEnableOption "WiFiman Desktop daemon";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.wifiman-desktop ];

    systemd.services.wifiman-desktop = {
      description = "wifiman-desktop";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.nettools
        pkgs.iw
        pkgs.openresolv
        pkgs.iproute2
        pkgs.wireguard-tools
        pkgs.procps
      ];
      environment = {
        BASE = "/var/lib/wifiman-desktop";
      };
      preStart = ''
        for file in ${pkgs.wifiman-desktop}/lib/wifiman-desktop/* ${pkgs.wifiman-desktop}/lib/wifiman-desktop/.env*; do
          [ -e "$file" ] || continue
          ln -sf "$file" "/var/lib/wifiman-desktop/$(basename "$file")"
        done
      '';
      serviceConfig = {
        User = "root";
        Restart = "always";
        RestartSec = 30;
        WorkingDirectory = "/var/lib/wifiman-desktop";
        StateDirectory = "wifiman-desktop";
        ExecStart = "${pkgs.wifiman-desktop}/lib/wifiman-desktop/wifiman-desktopd";
      };
    };
  };
}
