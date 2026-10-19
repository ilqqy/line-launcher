# NixOS module. Writes /etc/xdg/line-launcher/config.json, which Config.qml
# reads as the system-wide layer beneath any per-user config.json.
self: {
  config,
  lib,
  pkgs,
  ...
}: let
  options = import ./options.nix {inherit lib;};
  cfg = config.programs.line-launcher;

  stylixColors =
    if (config ? lib) && (config.lib ? stylix) && (config.lib.stylix ? colors)
    then config.lib.stylix.colors.withHashtag
    else null;
in {
  options.programs.line-launcher = options.mkOptions {
    defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.stylix.enable || stylixColors != null;
        message = "programs.line-launcher.stylix.enable is set but stylix is not active in this NixOS configuration.";
      }
    ];

    environment.systemPackages = [cfg.package];

    environment.etc."xdg/line-launcher/config.json".text =
      options.mkConfigJson {inherit cfg stylixColors;};

    # Runs through the same wrapper as the keybinding, so the PATH and the
    # QS_ICON_THEME it derives are identical; everything else comes from the
    # user manager's environment. NixOS gives every unit its own minimal PATH
    # (coreutils, grep, sed...) plus LOCALE_ARCHIVE and TZDIR; those are
    # removed, or applications launched from here would not find `firefox`.
    systemd.user.services.line-launcher = lib.mkIf cfg.resident {
      description = "line-launcher, resident and hidden until toggled";
      environment = {
        PATH = lib.mkForce null;
        LOCALE_ARCHIVE = lib.mkForce null;
        TZDIR = lib.mkForce null;
      };
      partOf = ["graphical-session.target"];
      after = ["graphical-session.target"];
      wantedBy = ["graphical-session.target"];
      # Without a compositor to connect to, Restart= would only loop.
      unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} --daemon";
        Restart = "always";
        RestartSec = 1;
      };
    };
  };
}
