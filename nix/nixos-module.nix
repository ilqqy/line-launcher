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
  };
}
