# line-launcher

An application launcher for Hyprland, written in [Quickshell](https://quickshell.org),
styled after macOS: a Spotlight-style search field over a Launchpad-style
icon grid, in one centred translucent panel blurred by the compositor. It
replaces rofi for applications, shell commands, custom actions and
`rofi -dmenu` pipelines such as `cliphist`.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Hyprland setup](#hyprland-setup)
- [Using the launcher](#using-the-launcher)
- [Keyboard and mouse](#keyboard-and-mouse)
- [Configuration](#configuration)
- [Command-line reference](#command-line-reference)
- [Theming](#theming)
- [Files and state](#files-and-state)
- [Development and tests](#development-and-tests)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)

## Features

- Search ported from rofi 2.x: token matching over name, generic name,
  executable, categories and keywords; normal, glob, fuzzy, regex and prefix
  matching methods; `-` negation; rofi's ranking and launch history
  (`rofi3.druncache` format, shareable with rofi).
- One ranked list for applications, custom actions and shell commands;
  applications and actions rank above command candidates.
- English/Russian keyboard-layout fallback: `вшысщкв` finds Discord.
- Category chips derived from `.desktop` `Categories=`, "All" first.
- A 5-column icon grid with edge fades and a gliding selection highlight.
- Shell-command mode (`>` prefix) and dmenu mode (piped stdin, e.g. the
  clipboard picker), both shown as Spotlight-style rows.
- Confirm-before-running for dangerous actions.
- Open: fade and scale-up (0.96 to 1, 150 ms ease-out). Close: the reverse
  (110 ms ease-in).
- Light or dark following the active pywal, wallust or matugen palette, with
  an automatically chosen readable accent; palette changes apply live.
- System icon theme with a generic fallback icon and a drawn letter tile when
  nothing resolves.
- Opens on Hyprland's focused monitor.

## Installation

### Flake

Run without installing:

```sh
nix run github:ilqqy/line-launcher
```

Add it as an input:

```nix
{
  inputs.line-launcher = {
    url = "github:ilqqy/line-launcher";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Outputs: `packages.<system>.default` (also `.line-launcher`),
`apps.<system>.default`, `homeManagerModules.default` (also
`.line-launcher`), `nixosModules.default` (also `.line-launcher`),
`devShells.<system>.default`, `formatter`. Systems: `x86_64-linux`,
`aarch64-linux`.

### Home Manager

```nix
{inputs, ...}: {
  imports = [inputs.line-launcher.homeManagerModules.default];

  programs.line-launcher = {
    enable = true;
    font = "Inter";
    terminal = "kitty -e";
  };
}
```

Installs the package and writes `$XDG_CONFIG_HOME/line-launcher/config.json`.

### NixOS

```nix
{inputs, pkgs, ...}: {
  imports = [inputs.line-launcher.nixosModules.default];

  programs.line-launcher = {
    enable = true;
    font = "Inter";
    terminal = "kitty -e";
  };

  # The module does not install fonts.
  fonts.packages = [pkgs.inter];
}
```

Same options; writes `/etc/xdg/line-launcher/config.json`. If both modules are
used, the per-user file overrides the system one key by key.

### Fonts

The panel uses Inter, and Inter Display (Inter's large optical size, shipped
in the same `inter` package) for the search field. `programs.line-launcher.font`
sets the family; when it is null, `"Inter"` is requested anyway. Inter Display
is used only while the family is `Inter`; any other family is used for the
field as well. Install the font yourself, for example with `pkgs.inter` in
`fonts.packages`. Without it, fontconfig substitutes another face.

### Icon theme

Icons come from the system icon theme. Qt only reads an icon theme from
qt6ct/KDE settings, and without one it resolves against hicolor alone, which
has no generic icons. The packaged wrapper therefore exports `QS_ICON_THEME`
from `gtk-icon-theme-name` in `$XDG_CONFIG_HOME/gtk-3.0/settings.ini`, unless
`QS_ICON_THEME` is already set. When running from a checkout (no wrapper), set
`QS_ICON_THEME` yourself.

For each result the launcher asks for the entry's icon name or absolute path,
falls back to the theme's `application-x-executable`, and, when neither
resolves, draws a rounded tile with the entry's first letter. A placeholder
tile holds the slot while an icon is loading, and grid rows below the fold
look their icons up only once they scroll into view.

## Hyprland setup

Hyprland 0.55+ Lua configuration:

```lua
hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("line-launcher --toggle"))
hl.bind("SUPER + V", hl.dsp.exec_cmd(
  "cliphist list | line-launcher | cliphist decode | wl-copy"
))

hl.layer_rule({
  match = { namespace = "line-launcher" },
  blur = true,
  ignore_alpha = 0.15,
  no_anim = true,
})
```

- `blur` blurs what is behind the panel.
- `ignore_alpha = 0.15` is required. The launcher is a transparent
  full-screen layer surface; blur applies only where its alpha exceeds 0.15,
  which is the panel (fill alpha 0.60 dark, 0.72 light) and not the shadow
  (kept at 0.14 or less) or the empty screen.
- `no_anim` disables Hyprland's layer animation; the launcher animates its own
  open and close, and the two would otherwise play on top of each other.

Use one binding for opening and closing, and make it `--toggle`. Do not add a
second binding that kills Quickshell separately. If Hyprland cannot find the
Home Manager package on its `PATH`, call it by profile path:

```lua
local launcher = os.getenv("HOME")
  .. "/.local/state/nix/profiles/home-manager/home-path/bin/line-launcher"
hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd(launcher .. " --toggle"))
```

A custom namespace (`--namespace NAME`) needs the same rule with that name.

## Using the launcher

### Layout

A 640x511 panel, centred horizontally, slightly above the vertical centre of
the focused monitor:

1. Search field: magnifier, query, clear button (shown while there is text).
2. Category chips.
3. Results: a 5-column grid (about 3.4 rows visible, scrolling) for
   applications, actions and commands found by ordinary search; rows for
   dmenu lines and `>` command mode.

The surface covers the whole monitor, so a click anywhere outside the panel
reaches the launcher and closes it.

### Search

Type to search. Results are shown in exactly the order the search engine
returns them. Desktop entries marked `NoDisplay` are hidden and duplicate
desktop IDs are removed.

With an empty query only applications and actions that have been launched
before are shown, most frecent first. On a fresh history the panel shows
"Start Typing to Search".

If the query matches no application or action, the other keyboard layout
(English/Russian) is tried; the text you typed stays in the field.

Applications with `Terminal=true` run in `terminal` (or `$TERMINAL`); with
neither set they run without a terminal and a warning is logged.

### Categories

Chips are built from the freedesktop main categories present among the
installed applications: Development, Education, Games (`Game`), Graphics,
Internet (`Network`), Media (`AudioVideo`, `Audio`, `Video`), Office,
Science, Settings, System, Utilities (`Utility`). A chip exists only if at
least one application has that category. Additional categories
(`WebBrowser`, `TextEditor`, `GTK`, `X-...`) are not chips.

A chip only hides results; it never reorders them. Actions and commands have
no categories and appear under "All" only. Because the empty query lists only
recently used applications, a chip with an empty query filters those: it
shows "No Recent Apps in X" until you type. A chip with no matching results
shows "No Results"; Enter then closes the launcher, as on an empty list.

### Shell commands

Commands take part in ordinary search: the typed text is offered as a
command (terminal icon), after any matching applications and actions,
together with matching command-history entries. Enter runs it through
`sh -c`.

Start the query with `>` to search commands only. The results become rows
under a "Commands" header: the typed command first, then history, most recent
first. Commands are matched literally (flags and punctuation are not
interpreted).

History: `$XDG_STATE_HOME/line-launcher/history.json`, most recent first,
duplicates moved to the top, capped at 200 entries.

Commands run with your user's authority, like a terminal.

### Actions

```nix
programs.line-launcher.actions = [
  { name = "Lock"; exec = "hyprlock"; }
  { name = "Suspend"; exec = "systemctl suspend"; }
  { name = "Reboot"; exec = "systemctl reboot"; confirm = true; }
  { name = "Power off"; exec = "systemctl poweroff"; icon = "system-shutdown"; confirm = true; }
];
```

Actions are matched by `name` and `exec` (`poweroff` finds "Power off") and
are ranked with applications. `icon` (theme name or absolute path) is shown
in the grid; without it the generic executable icon is used. `terminal = true`
runs the command in the configured terminal.

With `confirm = true` the first Enter arms the action: the highlight turns
the danger colour and the label reads "Press Enter to confirm". A second
Enter (or `Ctrl+m`) runs it. Holding Enter does not confirm; any other
non-modifier key or a change of selection disarms it.

### Clipboard and dmenu mode

Piping into `line-launcher` lists the piped lines instead of applications,
prints the chosen line to stdout and exits 0; Esc prints nothing and exits 1:

```sh
printf 'first\nsecond\n' | line-launcher
cliphist list | line-launcher | cliphist decode | wl-copy
```

Lines are shown as rows under an "Items" header (or the `--prompt` text),
without icons and without category chips. A line containing tabs shows its
second column but returns the whole line, as rofi's `-display-columns 2` does
for `cliphist`. Displayed lines are cut at `maxCharacters`.

## Keyboard and mouse

| Input | Action |
| --- | --- |
| typing | search |
| `Up` / `Down`, `Ctrl+p` / `Ctrl+n` | grid: previous / next row (rows: previous / next row). Up on the top row stays; Down into a shorter last row lands on its last cell |
| `Left` / `Right` | grid: previous / next cell in reading order (while the grid has results; otherwise the caret moves) |
| `Shift` or `Ctrl` + arrows | edit the text as in any field |
| `PageUp` / `PageDown` | grid: 3 rows; rows: 8 |
| `Tab` / `Shift+Tab` | next / previous category chip, wrapping. In dmenu and `>` mode (no chips): next / previous result |
| `Enter`, `Ctrl+m` | launch the selection (twice for `confirm = true` actions) |
| `Esc` | close |
| pointer motion over a tile or row | select it |
| click a tile or row | launch it |
| click a chip | switch category |
| click the clear button | clear the query |
| mouse wheel | scroll the results |
| click outside the panel | close |

Hover selects only when the pointer actually moves, so a pointer resting
where the panel opens does not take the selection from the keyboard.

Closing animates (fade and scale-down) after Esc, a launch, or a click
outside. Closing through `line-launcher --toggle` is instant: the wrapper
ends the running instance with `qs kill`.

## Configuration

### Module options

`programs.line-launcher.*` (Home Manager and NixOS):

| Option | Default | Effect |
| --- | --- | --- |
| `enable` | `false` | install and write `config.json` |
| `package` | flake package | package to install |
| `font` | `null` | font family; null requests Inter |
| `terminal` | `null` | terminal command for `Terminal=true` entries and `terminal = true` actions; null uses `$TERMINAL` |
| `colorsFile` | `null` | palette JSON path; null probes pywal, wallust, matugen (see [Theming](#theming)) |
| `colorsFormat` | `null` | `pywal`, `wallust` or `matugen`; inferred when null |
| `accentKey` | `"auto"` | palette key for the accent, or `auto` |
| `colors.foreground` | `null` | static fallback; reference colour for the `auto` accent choice |
| `colors.background` | `null` | static fallback; tints the panel and decides light or dark |
| `colors.accent` | `null` | static fallback accent |
| `colors.danger` | `"#d75f5f"` | confirm-state colour |
| `stylix.enable` | `false` | take the colour fallbacks from Stylix base05, base00, base0D |
| `maxCharacters` | `60` | display cut for dmenu lines |
| `actions` | `[]` | custom actions (`name`, `exec`, `icon`, `confirm`, `terminal`) |

Still accepted, written to `config.json`, but with no effect on the current
interface: `glowEnabled`, `glowRadius`, `glowOpacity`, `auraRadius`,
`auraOpacity`, `frameWidth`, `frameHeight`, `frameFillOpacity`, `topMargin`,
`whiskerLength`, `hookLength`, `visibleItems`, `listPerspective`. The panel's
size and look are set in [`Theme.qml`](#theming).

### config.json

Without a module, create `$XDG_CONFIG_HOME/line-launcher/config.json` with
the same keys (`colors` is an object, `actions` a list). Precedence, lowest
first:

1. built-in defaults (`Config.qml`),
2. `/etc/xdg/line-launcher/config.json`,
3. `$XDG_CONFIG_HOME/line-launcher/config.json`, or the `--config` file,
4. command-line flags.

Configuration and palette files are watched; edits apply to a running
launcher.

JSON-only keys (no module option):

| Key | Default | Effect |
| --- | --- | --- |
| `matchingMethod` | `"normal"` | `normal`, `glob`, `fuzzy`, `regex`, `prefix` |
| `sortMatches` | `false` | sort by distance instead of match quality |
| `sortingMethod` | `"normal"` | `normal` (Levenshtein) or `fzf` |
| `matchFields` | `"name,generic,exec,categories,keywords"` | desktop fields searched (`comment` and `all` also accepted) |
| `preferNameMatch` | `true` | rank name matches above generic/keyword/category/exec matches |
| `normalizeMatch` | `false` | strip accents before matching |
| `drunCache` | `line-launcher.druncache` | launch-history file: absolute, or relative to `$XDG_CACHE_HOME`; `"rofi3.druncache"` shares rofi's history |
| `commandAccent` | unset | accent while the `>` prefix is active |
| `fontSize` | `14` | no effect on the current interface |

## Command-line reference

```text
line-launcher [OPTIONS]
<command> | line-launcher [OPTIONS]      # dmenu mode
```

| Flag | Effect |
| --- | --- |
| `--toggle` | close the running launcher, or open it if none is running |
| `--prompt TEXT` | placeholder text; in dmenu mode also the list header |
| `--config PATH` | use an alternate `config.json` |
| `-n NAME`, `--namespace NAME` | layer-shell namespace (default `line-launcher`) |
| `--items N` | validated and accepted; no effect on the current interface |
| `-h`, `--help` | usage |

Without `--toggle`, a second launcher does not stack on top of a running one
(Quickshell `--no-duplicate`); piped invocations are independent.

## Theming

Colours come from the active palette. With `colorsFile` unset the launcher
probes, in order, `$XDG_CACHE_HOME/wal/colors.json` (pywal),
`$XDG_CACHE_HOME/wallust/colors.json` (wallust) and
`$XDG_CACHE_HOME/matugen/colors.json` (matugen); the first readable file
wins, and the static `colors` apply when none is found. Rewriting the
palette file recolours a running launcher.

- Light or dark: dark when the palette background's HSL lightness is below
  0.5. Text is white or black at fixed opacities in either mode.
- Panel: the palette background at 60% opacity (dark) or 72% (light), a 1 px
  inner border, a soft shadow.
- Accent: for pywal/wallust with `accentKey = "auto"`, whichever of
  `color1`...`color6` is furthest from the foreground in CIEDE2000; matugen
  uses its `primary` role. Used for the active chip, the caret and text
  selection. The chosen source and accent are printed to the log at startup.

The look is defined in [`Theme.qml`](Theme.qml), a singleton at the repo
root. Below its palette parsing, the "design tokens" section holds every
value the panel draws with:

| Group | Tokens (defaults) |
| --- | --- |
| type | `uiFont`, `displayFont`, `searchFontSize` 22 (Light), `labelFontSize` 12, `chipFontSize` 13, `rowFontSize` 14, `sectionFontSize` 12, `emptyTitleSize` 15, `emptyBodySize` 13 |
| colour | `textPrimary`, `textSecondary`, `textTertiary`, `placeholder`, `glyph`, `panelOpacity`, `panelFill`, `panelBorder`, `divider`, `shadowColor`, `selectionFill`, `dangerFill`, `chipFill`, `chipHoverFill`, `chipText`, `chipActiveFill`, `chipActiveText`, `clearFill`, `clearHoverFill`, `clearGlyph`, `caret`, `textSelection`, `fallbackIconFill` |
| radii | `radiusPanel` 20, `radiusTile` 14, `radiusRow` 10 |
| sizes, spacing | `panelPadding` 20, `searchHeight` 56, `chipHeight` 28, `gridColumns` 5, `cellWidth` 120, `cellHeight` 116, `iconSize` 56, `gridVisibleRows` 3.4, `pageRows` 3, `rowHeight` 40, `listPageRows` 8, `fadeSize` 28, `shadowBlur` 48, `shadowOffsetY` 16, `panelVerticalBias` 0.42, and the rest of the group; `panelWidth`/`panelHeight` are derived |
| icons | `fallbackIcon` (`application-x-executable`), `commandIcon` (`utilities-terminal`) |
| durations (ms) | `openDuration` 150, `closeDuration` 110, `closedScale` 0.96, `highlightDuration` 140, `scrollDuration` 180, `chipDuration` 180, `hoverDuration` 120, `fadeDuration` 120, `pressDuration` 90, `caretBlink` 530 |

To change the look, edit the tokens and restart the launcher (or rebuild the
package). Colour tokens choose per mode with `root.dark ? <dark> : <light>`.
Constraints:

- `panelFill` alpha must stay above the layer rule's `ignore_alpha` (0.15),
  or the blur behind the panel is dropped; `shadowColor` alpha must stay
  below it, or the shadow region gets blurred too.
- `closeDuration` must stay below 120 ms: the launcher quits 120 ms after Esc
  or a click outside (160 ms after a launch), and the last frame has to land
  first.

## Files and state

| Path | Purpose |
| --- | --- |
| `/etc/xdg/line-launcher/config.json` | system configuration |
| `$XDG_CONFIG_HOME/line-launcher/config.json` | user configuration |
| `$XDG_CACHE_HOME/line-launcher.druncache` | application/action launch history (rofi format, 25 entries) |
| `$XDG_STATE_HOME/line-launcher/history.json` | shell-command history |

## Development and tests

```sh
nix develop          # quickshell, Qt tooling, shellcheck, alejandra
QS_ICON_THEME=Papirus-Dark qs -p .    # run the checkout (any icon theme name)
./launcher.sh --toggle               # or through the wrapper script, with qs on PATH
```

### Test suite

```sh
./tests/run.sh
nix flake check
```

`tests/run.sh` runs headless (`QT_QPA_PLATFORM=offscreen`, isolated XDG
directories): the CLI wrapper (argument validation, dmenu output,
cancellation), `activation` (confirm and launch), `color` (CIEDE2000 and the
accent choice), `frame` (config layering, palette colours, the search field
key map), `search` (matching, ranking, history, actions, commands, dmenu,
layout fallback) and `detect` (palette auto-detection), and finally checks
that `shell.qml` compiles. It exits non-zero on any failure.

### Search baseline

```sh
tests/baseline/run.sh            # compare against tests/baseline/baseline.json
tests/baseline/run.sh --record   # rewrite baseline.json
```

The baseline guards the search engine. It runs `shell.qml` verbatim up to
its `window` section marker (providers, ranking, history), `rofi-search.js`
and the providers over the machine's live desktop-entry index. Launch and
command history come from the fixtures in `tests/baseline/fixtures/`. It
pushes the 25 queries in `tests/baseline/queries.json` through and writes
each ordered result list, plus the application catalog it ran against, as
JSON.

`BASELINE: IDENTICAL` (exit 0) means every query returned the same results
in the same order, with the same entry Enter would launch, as when the
baseline was recorded. Otherwise it prints `BASELINE: DIFFERS` and a unified
diff (exit 1). A change in installed applications shows up in the `catalog`
part of the diff; on a different machine, record a baseline first and compare
against that.

## Known limitations

- Hyprland's blur is applied per pixel, on or off by `ignore_alpha`; it
  cannot fade in with the panel. It switches on, at full strength, once the
  fading panel's alpha crosses the threshold, early in the open animation.
- The shadow must stay below `ignore_alpha`, so it is lighter than macOS's.
- Icon lookups are slow when the icon theme, or a theme it inherits (hicolor,
  breeze-dark for Papirus), has no `icon-theme.cache`: about 16 ms per icon,
  so the first screen of icons fades in over placeholders for roughly 0.3 s
  after the panel appears. NixOS builds no caches unless
  `gtk.iconCache.enable = true` (its default follows
  `services.xserver.enable`); with it, the same icons load in about 80 ms.
- `--toggle` closes instantly, without the close animation.
- The panel size is fixed by `Theme.qml`; there are no layout options in
  `config.json`.

## Troubleshooting

- **The launcher reopens instead of closing.** There must be exactly one
  binding, running `line-launcher --toggle`.
- **`unknown option: --toggle`.** Hyprland finds an older package; check
  `type -a line-launcher` and rebuild, or use the profile path above.
- **The whole monitor is blurred, or nothing is.** The layer rule must match
  the namespace (`line-launcher` unless `--namespace` is used) and set
  `ignore_alpha = 0.15`.
- **Letter tiles instead of icons.** No icon theme reached Quickshell: check
  `gtk-icon-theme-name` in `~/.config/gtk-3.0/settings.ini`, or set
  `QS_ICON_THEME`.
- **Wrong font.** Inter is not installed; `fc-match Inter` shows the
  substitute.
- **Colours do not update.** The startup log names the palette file and
  format in use; an explicit `colorsFile` disables probing.
- **Inspect or close instances.** `qs list --all`, `qs kill --path <qml dir>`.

## Credits

`rofi-search.js` is taken from
[wave-launcher](https://github.com/Kalkaro/wave-launcher) (MIT), which ports
the search, ranking and history logic from
[Rofi](https://github.com/davatorium/rofi) (MIT). Both licences are reproduced
in [`licenses/`](licenses/).

Everything else is MIT licensed; see [LICENSE](LICENSE).
