# line-launcher

A Wayland application launcher for Hyprland, written in [Quickshell](https://quickshell.org).
A translucent, Hyprland-blurred search frame with a line extending from both
sides, plus a transparent result lane.

![demo](docs/demo.gif)

<!-- TODO: record docs/demo.gif -->

- Applications, user-defined actions, shell commands and piped stdin, all
  behind one provider interface and one ranked list.
- Rofi's drun matching and launch history, ported verbatim (see
  [Credits](#credits)) -- point it at `~/.cache/rofi3.druncache` and your
  existing rofi history carries over.
- Ghost completion: typing `ste` draws `am` after the caret. A hint only --
  no key accepts it, since Tab moves the selection.
- Colours follow pywal / wallust / matugen at runtime. Change the wallpaper and
  a running launcher recolours -- no restart, no rebuild.
- Works as a dmenu replacement when stdin is a pipe.

## Run

```sh
nix run github:ilqqy/line-launcher
```

Or drop the binary into a shell:

```sh
nix shell github:ilqqy/line-launcher
line-launcher
```

Hacking on it:

```sh
nix develop
qs -p .          # runs straight from the checkout
./tests/run.sh   # headless assertions
```

## Configuration

### home-manager

Add the flake as an input and import `homeManagerModules.default`. Every option
is shown here; all of them have defaults, so a real configuration is much
shorter.

```nix
{
  inputs.line-launcher.url = "github:ilqqy/line-launcher";

  # ... inside your home-manager configuration:
  imports = [ inputs.line-launcher.homeManagerModules.default ];

  programs.line-launcher = {
    enable = true;
    # package = inputs.line-launcher.packages.${pkgs.system}.default;

    font = "JetBrainsMono Nerd Font";   # null uses the system font

    # All three default to null, which auto-detects: $XDG_CACHE_HOME/wal,
    # then wallust, then matugen. Set colorsFile only to override that.
    # Watched at runtime either way, so a wallpaper change recolours a
    # running launcher.
    colorsFile = null;
    colorsFormat = null;                # "pywal" | "wallust" | "matugen"
    accentKey = "auto";                 # or a key; ignored for matugen

    # Used when no palette is configured or found, or one cannot be parsed.
    colors = {
      foreground = "#c5c8c6";
      background = "#1d1f21";           # the legibility glow
      accent = "#5f87d7";
      danger = "#d75f5f";               # the confirm state
    };

    # Take foreground from base05, background from base00 and accent from
    # base0D instead.
    stylix.enable = false;

    # See Glow below. Radii are quoted at the default fontSize and scale
    # with it.
    glowEnabled = true;
    glowRadius = 8;                     # legibility halo, palette background
    glowOpacity = 0.55;
    auraRadius = 20;                    # selection aura, resolved accent
    auraOpacity = 0.35;

    frameWidth = 260;                   # central search box
    frameHeight = 44;
    frameFillOpacity = 0.42;            # lets compositor blur show through
    whiskerLength = 120;
    visibleItems = 5;
    listPerspective = 0;                # 1 fans the rows away from you
    maxCharacters = 60;                 # dmenu column truncation

    terminal = "kitty -e";              # for Terminal=true entries

    actions = [ ];                      # see Actions below
  };
}
```

There is a matching NixOS module at `nixosModules.default` with the same
options, which writes the config to `/etc/xdg/line-launcher/config.json`. A
per-user file wins over the system one, key by key.

### Without Nix

The modules only write a JSON file. Put the same thing at
`$XDG_CONFIG_HOME/line-launcher/config.json` by hand:

```json
{
  "font": "JetBrainsMono Nerd Font",
  "colorsFile": "/home/alice/.cache/wal/colors.json",
  "colorsFormat": "pywal",
  "accentKey": "auto",
  "colors": {
    "foreground": "#c5c8c6",
    "background": "#1d1f21",
    "accent": "#5f87d7",
    "danger": "#d75f5f"
  },
  "glowEnabled": true,
  "glowRadius": 8,
  "glowOpacity": 0.55,
  "auraRadius": 20,
  "auraOpacity": 0.35,
  "frameWidth": 260,
  "frameHeight": 44,
  "frameFillOpacity": 0.42,
  "whiskerLength": 120,
  "visibleItems": 5,
  "listPerspective": 0,
  "maxCharacters": 60,
  "terminal": "kitty -e",
  "actions": []
}
```

Both files are watched, so edits apply to a running launcher.

### Colours

With `colorsFile` unset, these are probed in order and the first that exists
wins, with the format inferred from which one hit:

| Path | Format |
| --- | --- |
| `$XDG_CACHE_HOME/wal/colors.json` | pywal |
| `$XDG_CACHE_HOME/wallust/colors.json` | wallust |
| `$XDG_CACHE_HOME/matugen/colors.json` | matugen |

Setting `colorsFile` skips probing. Either way the file is watched, so
regenerating it recolours a running launcher.

`accentKey` defaults to `"auto"`, which picks whichever of `color1` through
`color6` sits furthest from the resolved foreground in CIEDE2000, and re-picks
on every reload. A fixed key is a bet that one palette slot will always be
distinct from the foreground, and a near-monochrome wallpaper loses that bet:
every candidate comes back a slightly different grey and the selection outline
disappears against the rows. Naming a key explicitly overrides the
measurement.

Both decisions are reported on one line at startup, so a launcher that came up
in the wrong colours can be diagnosed without instrumenting anything:

```
line-launcher: colors=/home/alice/.cache/wal/colors.json (probed, pywal); \
accent=color1 #DEB2A6 (auto, deltaE2000 16.6 from foreground #c4c5c6)
```

The accent is used for the selection outline and the typed query, and nothing
else -- see Glow below.

### Glow

The background is transparent by design, which means a pale wallpaper leaves
the strokes and the text with nothing to sit against. Rather than put a panel
or a scrim behind them, the content is given its own contrast: two halos, with
different colours and different jobs.

**The legibility glow** sits under the text and frame strokes, in
`colors.background` -- the palette's own background, not black, so a light
scheme gets a light halo instead of outlining its pale text in soot. It is
traced from the shape of the content, so a glyph sits in its own small pool of
colour and the space between glyphs stays transparent. Tight and dim on
purpose: `glowRadius` 8, `glowOpacity` 0.55.

`glowOpacity` is the opacity of the blurred silhouette, not the opacity of
what lands beside a glyph. Blurring a 1px stem across 8px spreads it thin, the
same way `text-shadow: 0 0 8px` does in CSS. Measured against a pale
wallpaper, in contrast ratio of the darkest pixel against the local
background:

| glowRadius | glowOpacity | result label |
| --- | --- | --- |
| — | off | 1.41:1 |
| 8 | 0.55 (default) | 1.61:1 |
| 4 | 0.55 | 1.68:1 |
| 8 | 1.0 | 1.83:1 |
| 4 | 1.0 | 2.01:1 |

Turn it up if your wallpapers are brighter than mine.

**The accent aura** is worn by two things: the selection outline, and the
typed query. Nothing else. Wider and softer than the legibility glow --
`auraRadius` 20, `auraOpacity` 0.35 -- so what you are steering and what it
has landed on light up together. The typed query uses a much stronger version
of that aura plus a maximum-contrast, semibold glyph colour. The ghost
completion does not get either treatment: it is a suggestion, not something
you typed. Neither does the prompt.

Around the outline it is drawn in whatever colour the outline currently is, so
it crossfades into `colors.danger` along with the stroke when an action asks
for its confirming Enter. On the query it follows the accent in force,
including a provider's own -- so the field recolours with the outline when a
prefix like `>` is active.

Both are traced from their complete silhouette. In particular, the outline is
blurred as one rounded ring rather than as four separate edge shadows: adjacent
edges therefore cannot stack their opacity into bright spots at the corners.
The query uses 2.5 times `auraOpacity`, capped at 1.0, so the typed text reads
brighter than the outline without changing the quieter ghost completion or
prompt.

Both radii are quoted at the default `fontSize` and scale with it: a halo is a
proportion of the type it sits under, so a launcher configured larger gets a
proportionally larger one rather than a hairline.

`glowEnabled = false` removes both. Not hidden, not made transparent -- the
effects are never constructed, so there is no layer and nothing to render
through.

Neither glow costs the launcher its rest. Measured on a real scene graph:
identical frame counts with the glow on and off, zero frames swapped over two
seconds of an idle launcher, and zero again in the two seconds after the
selection lands. The aura travels as part of the outline, and the scene returns
to rest once its geometry settles.

### The resting state

With an empty query the list shows launch history, most frecent first, and
nothing else. Until something has been launched it shows no rows at all --
just the frame. rofi falls back to alphabetical order once history runs out;
that is dropped here, because alphabetical order is not a meaningful resting
state, it only parks the selection on whatever sorts first.

Piped input (`--dmenu`) and command history keep the order they arrived in;
that order is the caller's, not a ranking.

### Keys the Nix modules do not expose

These are read from `config.json` only. The defaults are stock
`rofi -dump-config` values, and there is rarely a reason to change them.

| Key | Default | Meaning |
| --- | --- | --- |
| `matchingMethod` | `"normal"` | `normal`, `glob`, `fuzzy`, `regex` or `prefix` |
| `sortMatches` | `false` | sort by distance rather than by match quality |
| `sortingMethod` | `"normal"` | `normal` (levenshtein) or `fzf` |
| `matchFields` | `"name,generic,exec,categories,keywords"` | rofi's `drun-match-fields` |
| `preferNameMatch` | `true` | a name hit outranks an exec hit |
| `normalizeMatch` | `false` | strip accents before matching |
| `drunCache` | `$XDG_CACHE_HOME/line-launcher.druncache` | launch history, in rofi's format |
| `commandAccent` | unset | accent used while the `>` prefix is active |

Set `drunCache` to `"rofi3.druncache"` to share launch history with rofi
itself -- the file format is byte-for-byte the same.

## Actions

Actions are ranked in the same list as applications -- no section, no tab.
Nothing ships by default; this is the usual power menu.

```nix
programs.line-launcher.actions = [
  {
    name = "Lock";
    exec = "hyprlock";
  }
  {
    name = "Suspend";
    exec = "systemctl suspend";
  }
  {
    name = "Reboot";
    exec = "systemctl reboot";
    confirm = true;
  }
  {
    name = "Power off";
    exec = "systemctl poweroff";
    confirm = true;
  }
  {
    name = "Log out";
    exec = "hyprctl dispatch exit";
    confirm = true;
  }
];
```

With `confirm = true`, the first Enter does not launch. The selection outline
turns to `colors.danger` and the word `confirm` appears on the right; a second
Enter runs it, and any other key cancels.

Actions match on their `exec` line as well as their name, so typing
`poweroff` finds `Power off`.

## Piped input

When stdin is not a terminal, line-launcher lists the piped lines instead of
applications, prints the chosen line to stdout, and exits 1 with no output if
you press Escape. The drun, actions and command providers switch off.

```sh
cliphist list | line-launcher | cliphist decode | wl-copy
```

A line containing tabs displays its second tab-separated column but returns the
whole original line, matching rofi's `-display-columns 2` -- which is what makes
the `cliphist` pipeline above work. The displayed part is truncated at
`maxCharacters`.

## Command mode

Input beginning with `>` runs a shell command instead of searching
applications. The list shows previously executed commands; the typed command is
always offered first, so a plain Enter runs exactly what you typed. History is
kept in `$XDG_STATE_HOME/line-launcher/history.json`, capped at 200 entries.

## Keybindings

| Key | Action |
| --- | --- |
| `Up` / `Ctrl+p` / `Shift+Tab` | previous result |
| `Down` / `Ctrl+n` / `Tab` | next result |
| `Enter` | launch the selection (twice, for a `confirm` action) |
| `Esc` | close |

Tab and Shift+Tab used to accept the ghost completion. Nothing is bound to
that now -- the ghost is still drawn as a hint, but it is not something you
can take.

It opens by fading up while the two whiskers drift in from a tenth of the way
out towards the screen edge, over 320ms.

Enter and Escape close differently on purpose: Enter collapses the frame -- the
box closes to a line, the whiskers slide off screen, and the outline flattens
to a line -- while Escape just fades in place.

The selection outline travels on the same 150ms curve the lane slides on, and
lands on its row rather than past it. While a key is held the lane shortens
that slide to the repeat's own interval, so the rows keep sliding smoothly
instead of teleporting and nothing falls behind. Rows fade with how far down
the lane they sit, not with their distance from the selection -- the lane looks
the same wherever the selection is.

Hyprland:

```lua
bind = SUPER, R, exec, line-launcher

hl.layer_rule({
  match = { namespace = "line-launcher" },
  blur = true,
  ignore_alpha = 0.15,
})
```

`ignore_alpha` is important because the launcher owns a transparent
full-screen layer surface. It confines compositor blur to the translucent
center frame instead of blurring the entire monitor.

## Command-line flags

| Flag | Effect |
| --- | --- |
| `--items N` | show `N` result rows for this invocation |
| `--no-ghost` | disable ghost completion text |
| `--prompt TEXT` | placeholder text for the input field |
| `--config PATH` | use an alternate `config.json` |
| `-n`, `--namespace NAME` | layer-shell namespace for the surface (default `line-launcher`) |

Flags override the config file, which overrides the built-in defaults.

The namespace is what a compositor matches its layer rules against, and it is
used exactly as given -- `line-launcher -n wave-launcher` produces a surface
named `wave-launcher` and nothing else:

```
hl.layer_rule({
  match = { namespace = "wave-launcher" },
  blur = true,
  ignore_alpha = 0.15,
})
```

## Credits

`rofi-search.js` is taken verbatim from
[wave-launcher](https://github.com/Kalkaro/wave-launcher) (MIT), which ports the
search, ranking and history logic from
[Rofi](https://github.com/davatorium/rofi)'s drun mode (`helper.c`, `drun.c`,
`history.c`), also MIT. Both licences are reproduced in
[`licenses/`](licenses/).

Everything else is MIT, see [LICENSE](LICENSE).
# line-launcher
