# Shared between the home-manager and NixOS modules: one option set, one JSON
# writer. The only difference between the two modules is where the resulting
# config.json is placed.
{lib}: let
  inherit (lib) mkOption mkEnableOption types literalExpression;
in rec {
  actionType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Label shown in the result list and matched by the fuzzy scorer.";
        example = "Power off";
      };

      exec = mkOption {
        type = types.str;
        description = "Command run with `sh -c` when the action is launched.";
        example = "systemctl poweroff";
      };

      icon = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Freedesktop icon name. Falls back to a generic icon when null.";
        example = "system-shutdown";
      };

      confirm = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Require a second Enter before running. The first Enter recolours the
          selection outline to {option}`colors.danger` and replaces the result
          counter with the word "confirm"; any other key cancels.
        '';
      };

      terminal = mkOption {
        type = types.bool;
        default = false;
        description = "Run the command inside {option}`terminal` rather than detached.";
      };
    };
  };

  mkOptions = {defaultPackage}: {
    enable = mkEnableOption "line-launcher, a Wayland application launcher";

    package = mkOption {
      type = types.package;
      default = defaultPackage;
      defaultText = literalExpression "line-launcher.packages.\${pkgs.system}.default";
      description = "The line-launcher package to use.";
    };

    font = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Font family for the input field and result names. Null uses the system default.";
      example = "JetBrainsMono Nerd Font";
    };

    colorsFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Absolute path to a JSON palette, watched at runtime. Rewriting it --
        which is what pywal, wallust and matugen do on a wallpaper change --
        recolours a running launcher with no restart and no rebuild.

        When null, the standard output path of each supported generator is
        probed in turn -- `$XDG_CACHE_HOME/wal/colors.json`, then
        `wallust/colors.json`, then `matugen/colors.json` -- and the first
        that exists is used, with {option}`colorsFormat` inferred from which
        one hit. A probed file is watched exactly like a configured one.

        Setting this explicitly skips probing entirely. When nothing is set
        and nothing is found, or when the file cannot be read or parsed, the
        static {option}`colors` below are used instead.
      '';
      example = "/home/alice/.cache/wal/colors.json";
    };

    colorsFormat = mkOption {
      type = types.nullOr (types.enum ["pywal" "wallust" "matugen"]);
      default = null;
      description = ''
        Shape of {option}`colorsFile`.

        `pywal` and `wallust` read `special.foreground` and
        `colors.<accentKey>`, and also accept a flat palette at the top level.
        `matugen` reads the `dark` scheme's `primary`, `on_surface` and
        `error` roles.

        Null infers the format from whichever probe found the palette, and
        falls back to `pywal` when {option}`colorsFile` is set but this is not.
      '';
      example = "wallust";
    };

    accentKey = mkOption {
      type = types.str;
      default = "auto";
      description = ''
        Palette key used as the accent colour, or `"auto"`.

        `"auto"` measures instead of guessing: at every palette load it picks
        whichever of `color1` through `color6` sits furthest from the resolved
        foreground in CIEDE2000, and re-picks when the wallpaper changes. A
        fixed key is a bet that one slot will always be distinct from the
        foreground, and that bet loses on a near-monochrome palette -- every
        candidate comes back a slightly different grey and the selection
        outline disappears against the rows.

        Naming a key explicitly overrides the measurement. Ignored entirely
        for the matugen format, which has named roles rather than a palette.
      '';
      example = "color6";
    };

    colors = {
      foreground = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Static fallback for text, whiskers and hooks.";
        example = "#c5c8c6";
      };

      background = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Static fallback for the legibility glow. Deliberately the scheme's
          background rather than black: on a light scheme the halo has to be
          light too, or the glow meant to make pale text readable would
          outline it in soot.
        '';
        example = "#1d1f21";
      };

      accent = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Static fallback for the selection outline.";
        example = "#5f87d7";
      };

      danger = mkOption {
        type = types.str;
        default = "#d75f5f";
        description = "Outline colour while an action is waiting for its confirming Enter.";
      };
    };

    stylix.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Take {option}`colors.foreground` from base05, {option}`colors.background`
        from base00 and {option}`colors.accent` from base0D of the active stylix
        scheme. Explicitly set colours still
        win; {option}`colorsFile` still overrides both at runtime.
      '';
    };

    glowEnabled = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Draw the two halos. The background is transparent by design, so on a
        pale wallpaper the strokes and the text have nothing to sit against;
        these give the content its own contrast without putting a panel behind
        it.

        Set false and the launcher renders exactly as it would without the
        feature: the effects are never constructed, so nothing is layered and
        nothing is blurred.
      '';
    };

    glowRadius = mkOption {
      type = types.ints.positive;
      default = 8;
      description = ''
        Reach in pixels of the legibility halo under the text, the strokes and
        the icons, in {option}`colors.background`.

        Quoted at the default {option}`fontSize` and scaled with it: a halo is
        a proportion of the type it sits under, so a launcher configured larger
        gets a proportionally larger one rather than a hairline.
      '';
    };

    glowOpacity = mkOption {
      type = types.numbers.between 0.0 1.0;
      default = 0.55;
      description = ''
        Opacity of the legibility halo.

        This is the opacity of the blurred silhouette, not the peak opacity
        next to a glyph: blurring a 1px stem across 8px spreads it thin, so
        what lands beside the stroke is nearer a tenth. It behaves like CSS
        `text-shadow: 0 0 8px`, which is the same construction. Measured
        against a pale wallpaper, the default lifts a result label from 1.41:1
        to 1.61:1 and the result counter from 1.05:1 to 1.21:1; the strongest
        setting that stays subtle, {option}`glowRadius` 4 with this at 1.0,
        reaches 2.01:1 and 1.50:1.
      '';
    };

    auraRadius = mkOption {
      type = types.ints.positive;
      default = 20;
      description = ''
        Reach in pixels of the accent aura around the selection outline, and
        nowhere else. Wider and softer than {option}`glowRadius`, because this
        one is meant to be seen rather than to go unnoticed.

        Scaled with {option}`fontSize` for the same reason as
        {option}`glowRadius`.
      '';
    };

    auraOpacity = mkOption {
      type = types.numbers.between 0.0 1.0;
      default = 0.35;
      description = ''
        Opacity of the accent aura at the outline's own edge, falling to
        nothing over {option}`auraRadius`. Around the outline this one keeps
        its core, so the number is what it looks like.

        The aura is drawn in whatever colour the outline currently is, so it
        follows the accent and crossfades into {option}`colors.danger` with the
        stroke when an action asks for its confirming Enter.

        The typed query wears the same aura, in the accent in force. That one
        is a blur rather than a distance falloff, because glyphs are not
        rectangles, so it lands far dimmer at the same number -- measured, it
        shifts its region by 0.005 in red-against-blue on a pale wallpaper.
        Raise this if you want the query to announce itself. The ghost
        completion and the prompt are left plain: neither was typed.
      '';
    };

    frameWidth = mkOption {
      type = types.ints.positive;
      default = 260;
      description = "Distance in pixels between the inner ends of the two whiskers.";
    };

    whiskerLength = mkOption {
      type = types.ints.positive;
      default = 50;
      description = "Length in pixels of each horizontal whisker stroke.";
    };

    hookLength = mkOption {
      type = types.ints.positive;
      default = 16;
      description = "Height in pixels of the vertical hook at each whisker's inner end.";
    };

    visibleItems = mkOption {
      type = types.ints.positive;
      default = 5;
      description = "Number of result rows shown before the lane starts scrolling.";
    };

    listPerspective = mkOption {
      type = types.numbers.between 0 1;
      default = 0;
      description = ''
        How much of the receding fan the result lane draws. 0, the default, is
        a straight dropdown: even steps, no tilt, rows at full width. 1 is the
        full projection, where rows below the first recede and converge.
      '';
      example = 1;
    };

    maxCharacters = mkOption {
      type = types.ints.positive;
      default = 60;
      description = "Truncation width for displayed dmenu lines.";
    };

    terminal = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Command used to run desktop entries with `Terminal=true` and actions
        with {option}`terminal = true`. The command to run is appended as
        further arguments.
      '';
      example = "kitty -e";
    };

    actions = mkOption {
      type = types.listOf actionType;
      default = [];
      description = ''
        User-defined actions, ranked in the same list as applications. Empty by
        default; see the README for a worked power-menu example.
      '';
      example = literalExpression ''
        [
          {
            name = "Power off";
            exec = "systemctl poweroff";
            icon = "system-shutdown";
            confirm = true;
          }
        ]
      '';
    };
  };

  # Emits the config.json consumed by Config.qml. Nulls are dropped so that
  # unset options fall through to the QML built-in defaults rather than
  # blanking them out.
  mkConfigJson = {
    cfg,
    stylixColors ? null,
  }: let
    resolved = {
      foreground =
        if cfg.colors.foreground != null
        then cfg.colors.foreground
        else if cfg.stylix.enable && stylixColors != null
        then stylixColors.base05
        else null;

      accent =
        if cfg.colors.accent != null
        then cfg.colors.accent
        else if cfg.stylix.enable && stylixColors != null
        then stylixColors.base0D
        else null;

      background =
        if cfg.colors.background != null
        then cfg.colors.background
        else if cfg.stylix.enable && stylixColors != null
        then stylixColors.base00
        else null;

      danger = cfg.colors.danger;
    };

    dropNulls = lib.filterAttrs (_: v: v != null);

    document =
      dropNulls {
        inherit
          (cfg)
          font
          colorsFile
          colorsFormat
          accentKey
          glowEnabled
          glowRadius
          glowOpacity
          auraRadius
          auraOpacity
          frameWidth
          whiskerLength
          hookLength
          visibleItems
          listPerspective
          maxCharacters
          terminal
          ;
      }
      // {
        colors = dropNulls resolved;
        actions = map (a: dropNulls {inherit (a) name exec icon confirm terminal;}) cfg.actions;
      };
  in
    builtins.toJSON document;
}
