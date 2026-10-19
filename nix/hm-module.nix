# home-manager module. Writes $XDG_CONFIG_HOME/line-launcher/config.json.
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
        message = "programs.line-launcher.stylix.enable is set but stylix is not active in this home-manager configuration.";
      }
    ];

    home.packages = [cfg.package];

    xdg.configFile."line-launcher/config.json".text =
      options.mkConfigJson {inherit cfg stylixColors;};

    # Runs through the same wrapper as the keybinding, so the PATH and the
    # QS_ICON_THEME it derives are identical; everything else comes from the
    # user manager's environment, which this deliberately does not override.
    systemd.user.services.line-launcher = lib.mkIf cfg.resident {
      Unit = {
        Description = "line-launcher, resident and hidden until toggled";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
        # Without a compositor to connect to, Restart= would only loop.
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} --daemon";
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
