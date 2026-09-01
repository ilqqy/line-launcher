# line-launcher

`line-launcher` is a text-first Wayland launcher for Hyprland, built with
[Quickshell](https://quickshell.org). It appears at the top centre of the
focused monitor as a translucent, compositor-blurred frame with horizontal
lines on both sides.

It can launch desktop applications, run arbitrary shell commands, expose
custom actions such as power off and reboot, and replace `rofi -dmenu` in
pipelines such as `cliphist`.

## Contents

- [Quick start](#quick-start)
- [Installation](#installation)
- [Hyprland setup](#hyprland-setup)
- [Using the launcher](#using-the-launcher)
- [Keyboard controls](#keyboard-controls)
- [Complete configuration](#complete-home-managernixos-configuration)
- [JSON configuration](#json-configuration-without-a-module)
- [Colours and visual effects](#colours-and-visual-effects)
- [Command-line reference](#command-line-reference)
- [Troubleshooting](#troubleshooting)
- [Development and tests](#development-and-tests)

## Features

- One ranked list for applications, custom actions, and shell commands.
- A real hotkey toggle: press Win once to open and press it again to close.
- Rofi-compatible application matching, ranking, and launch history.
- Normal, glob, fuzzy, regex, and prefix matching methods.
- Shell-command history with an optional command-only `>` prefix.
- Applications and actions rank above raw command candidates in combined search.
- Dmenu-compatible piped input, including `cliphist` tab-column handling.
- Confirm-before-running support for dangerous actions.
- Live pywal, wallust, matugen, or Stylix colours.
- Automatic selection of a readable palette accent.
- Hyprland blur limited to the translucent centre frame.
- Adjustable frame size, position, result count, glow, aura, and perspective.
- Focused-monitor placement and HiDPI pixel snapping.
- Text-only results: no icons are loaded or rendered.
- Centred, bright typed text with no ghost autocomplete.
- Separate opening, launch, and cancellation animations.

## Quick start

Run it without installing:

```sh
nix run github:ilqqy/line-launcher
```

Open a shell containing the launcher:

```sh
nix shell github:ilqqy/line-launcher
line-launcher
```

For a compositor shortcut, use `--toggle`, not the plain command:

```sh
line-launcher --toggle
```

The first call opens it. Calling the same command again closes the existing
Quickshell instance. Normal launcher invocations also use Quickshell's
single-instance protection, so overlays cannot accidentally stack.

## Installation

### Home Manager

Add the input to your flake:

```nix
{
  inputs.line-launcher = {
    url = "github:ilqqy/line-launcher";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Import the module in your Home Manager configuration:

```nix
{inputs, ...}: {
  imports = [inputs.line-launcher.homeManagerModules.default];

  programs.line-launcher = {
    enable = true;
    font = "JetBrainsMono Nerd Font";
    terminal = "kitty -e";
  };
}
```

The module installs the package and writes
`$XDG_CONFIG_HOME/line-launcher/config.json`.

### NixOS module

The NixOS module has the same options and writes
`/etc/xdg/line-launcher/config.json`:

```nix
{inputs, ...}: {
  imports = [inputs.line-launcher.nixosModules.default];

  programs.line-launcher = {
    enable = true;
    terminal = "kitty -e";
  };
}
```

If both modules are used, the per-user configuration overrides the system
configuration key by key.

### Local checkout

For development or testing local changes:

```sh
git clone https://github.com/ilqqy/line-launcher
cd line-launcher
nix develop
qs -p .
```

The wrapper can also run directly when `qs` is already on `PATH`:

```sh
./launcher.sh --toggle
```

## Hyprland setup

### Hyprland 0.55+ Lua configuration

This binds the left Win key by itself. The same key opens and closes the
launcher:

```lua
hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("line-launcher --toggle"))

hl.layer_rule({
  match = { namespace = "line-launcher" },
  blur = true,
  ignore_alpha = 0.15,
})
```

If a helper already adds `SUPER +`, use only `SUPER_L` when calling it:

```lua
local function bind(keys, dispatcher, flags)
  hl.bind("SUPER + " .. keys, dispatcher, flags)
end

bind("SUPER_L", hl.dsp.exec_cmd("line-launcher --toggle"))
```

Do not add a second Win binding that separately kills Quickshell. Opening and
closing must both go through `line-launcher --toggle`; two independent close
handlers can race and reopen the launcher.

`ignore_alpha` matters because the launcher owns a transparent full-screen
layer surface. It confines blur to the translucent frame instead of blurring
the entire monitor.

If Hyprland cannot find Home Manager packages in its `PATH`, use a stable
profile path:

```lua
local launcher = os.getenv("HOME")
  .. "/.local/state/nix/profiles/home-manager/home-path/bin/line-launcher"

hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd(launcher .. " --toggle"))
```

## Using the launcher

### Applications

Start typing an application name. Desktop entries are matched using their
name, generic name, executable, categories, and keywords. Entries marked
`NoDisplay` are hidden, and duplicate desktop IDs are removed.

Applications with `Terminal=true` are opened with `programs.line-launcher.terminal`
or `$TERMINAL`. When neither is set, the application is run without a terminal
and a warning is written to the launcher log.

With an empty query, only previously launched applications and actions are
shown, ordered by frecency. On a new installation the empty launcher therefore
shows only the input frame until something has been launched.

### Shell commands

Shell commands participate in ordinary search alongside applications and
actions, but matching applications/actions are presented first. Type a command
such as:

```text
cliphist wipe
```

The exact typed command appears as a result. Press Enter to execute it through
`sh -c`.

Begin the query with `>` to search commands only:

```text
>systemctl --user restart waybar
```

Executed commands are saved most-recent-first in
`$XDG_STATE_HOME/line-launcher/history.json`. Duplicate commands are moved to
the top, and history is capped at 200 entries.

Commands have the same authority as commands entered in a terminal. Review a
command before pressing Enter, especially if it modifies or deletes files.

### Custom actions and power controls

Actions appear in the same search results as applications. This example adds
lock, suspend, reboot, power-off, and logout controls:

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

Actions are matched by both `name` and `exec`, so `poweroff` finds the
`Power off` action.

When `confirm = true`, the first Enter arms the action: the selection changes
to the danger colour and `confirm` appears on the right. A second Enter runs
the action. Any non-modifier key cancels confirmation.

Set `terminal = true` on an action to run it inside the configured terminal.
The legacy `icon` action field is accepted for compatibility but ignored,
because this launcher intentionally renders no icons.

### Dmenu and cliphist

Piping stdin into `line-launcher` switches it into dmenu mode. Application,
action, and command providers are disabled for that invocation. The selected
original line is printed to stdout:

```sh
printf 'first\nsecond\nthird\n' | line-launcher
```

Escape prints nothing and exits with status 1. Selecting an item exits with
status 0.

For clipboard history:

```sh
cliphist list | line-launcher | cliphist decode | wl-copy
```

Suggested Hyprland binding:

```lua
hl.bind("SUPER + V", hl.dsp.exec_cmd(
  "cliphist list | line-launcher | cliphist decode | wl-copy"
))
```

When a piped line contains tabs, the second tab-separated column is displayed
but the complete original line is returned. This matches the behavior needed
for `cliphist` and Rofi's `-display-columns 2`. Displayed lines are truncated
according to `maxCharacters`.

## Keyboard controls

| Key | Action |
| --- | --- |
| `Win` | open or close when the compositor binding uses `--toggle` |
| `Up`, `Ctrl+p`, `Shift+Tab` | select the previous result |
| `Down`, `Ctrl+n`, `Tab` | select the next result |
| `Enter`, `Ctrl+m` | launch the selected result |
| `Enter` twice | run an action with `confirm = true` |
| `Esc` | close without launching |

Typed text is centred in the frame. There is deliberately no inline or ghost
autocomplete; the highlighted row is the only completion suggestion.
Unselected results remain slightly dimmer than the selection, but use a
brighter foreground than the placeholder so lower rows stay readable over the
wallpaper.

## Complete Home Manager/NixOS configuration

Every module option is shown below. All options have defaults, so only set the
ones you want to change.

```nix
programs.line-launcher = {
  enable = true;

  # Normally supplied automatically by the imported module.
  # package = inputs.line-launcher.packages.${pkgs.system}.default;

  font = "JetBrainsMono Nerd Font"; # null uses the system default
  terminal = "kitty -e";            # null falls back to $TERMINAL

  # null auto-detects pywal, wallust, or matugen.
  colorsFile = null;
  colorsFormat = null;               # null | "pywal" | "wallust" | "matugen"
  accentKey = "auto";                # auto, color1 ... color6, or another key

  colors = {
    foreground = "#c5c8c6";
    background = "#1d1f21";
    accent = "#5f87d7";
    danger = "#d75f5f";
  };

  stylix.enable = false;

  glowEnabled = true;
  glowRadius = 8;
  glowOpacity = 0.55;
  auraRadius = 20;
  auraOpacity = 0.35;

  frameWidth = 260;
  frameHeight = 44;
  frameFillOpacity = 0.42;
  topMargin = 36;
  whiskerLength = 120;
  visibleItems = 5;
  listPerspective = 0;               # 0 = flat, 1 = full receding fan
  maxCharacters = 60;

  actions = [];
};
```

### Module option reference

| Option | Default | Purpose |
| --- | --- | --- |
| `enable` | `false` | install and configure the launcher |
| `package` | flake package | launcher package to install |
| `font` | `null` | input and result font family |
| `terminal` | `null` | terminal command for terminal applications/actions |
| `colorsFile` | `null` | explicit palette JSON path; disables auto-detection |
| `colorsFormat` | `null` | `pywal`, `wallust`, or `matugen`; inferred when null |
| `accentKey` | `"auto"` | palette accent key or automatic contrast selection |
| `colors.foreground` | `null` | static text and stroke colour |
| `colors.background` | `null` | static frame and legibility-glow colour |
| `colors.accent` | `null` | static query and selection colour |
| `colors.danger` | `"#d75f5f"` | confirmation-state colour |
| `stylix.enable` | `false` | use Stylix base05, base00, and base0D fallbacks |
| `glowEnabled` | `true` | construct both contrast effects |
| `glowRadius` | `8` | legibility-halo radius at the default font size |
| `glowOpacity` | `0.55` | legibility-halo opacity |
| `auraRadius` | `20` | selection/query accent-aura radius |
| `auraOpacity` | `0.35` | accent-aura opacity |
| `frameWidth` | `260` | centre-frame width in pixels |
| `frameHeight` | `44` | centre-frame height in pixels |
| `frameFillOpacity` | `0.42` | translucent frame fill opacity |
| `topMargin` | `36` | distance from the monitor's top edge |
| `whiskerLength` | `120` | length of each side line |
| `hookLength` | `16` | deprecated compatibility option; currently unused |
| `visibleItems` | `5` | visible result rows before scrolling |
| `listPerspective` | `0` | result-lane projection from flat (`0`) to full (`1`) |
| `maxCharacters` | `60` | maximum displayed dmenu-line length |
| `actions` | `[]` | custom searchable actions |

Each action supports:

| Field | Default | Purpose |
| --- | --- | --- |
| `name` | required | displayed and searchable action name |
| `exec` | required | command executed through `sh -c` |
| `confirm` | `false` | require a second Enter |
| `terminal` | `false` | run inside the configured terminal |
| `icon` | `null` | deprecated and ignored |

## JSON configuration without a module

Create `$XDG_CONFIG_HOME/line-launcher/config.json` (normally
`~/.config/line-launcher/config.json`):

```json
{
  "font": "JetBrainsMono Nerd Font",
  "fontSize": 14,
  "terminal": "kitty -e",
  "frameWidth": 260,
  "frameHeight": 44,
  "frameFillOpacity": 0.42,
  "topMargin": 36,
  "whiskerLength": 120,
  "visibleItems": 5,
  "listPerspective": 0,
  "maxCharacters": 60,
  "glowEnabled": true,
  "glowRadius": 8,
  "glowOpacity": 0.55,
  "auraRadius": 20,
  "auraOpacity": 0.35,
  "accentKey": "auto",
  "colors": {
    "foreground": "#c5c8c6",
    "background": "#1d1f21",
    "accent": "#5f87d7",
    "danger": "#d75f5f"
  },
  "actions": []
}
```

Configuration precedence, from lowest to highest, is:

1. Built-in defaults.
2. `/etc/xdg/line-launcher/config.json`.
3. `$XDG_CONFIG_HOME/line-launcher/config.json`, or the file passed with
   `--config`.
4. Command-line overrides.

Configuration and palette files are watched. Saving a change updates a running
launcher without a restart or rebuild.

### Advanced JSON-only matching keys

These settings are accepted in `config.json` but are not exposed as Nix module
options:

| Key | Default | Purpose |
| --- | --- | --- |
| `fontSize` | `14` | font size in pixels; row metrics and glow scale with it |
| `matchingMethod` | `"normal"` | `normal`, `glob`, `fuzzy`, `regex`, or `prefix` |
| `sortMatches` | `false` | sort by distance instead of match quality |
| `sortingMethod` | `"normal"` | `normal` (Levenshtein) or `fzf` distance |
| `matchFields` | `"name,generic,exec,categories,keywords"` | desktop fields included in matching |
| `preferNameMatch` | `true` | rank a name match ahead of an executable match |
| `normalizeMatch` | `false` | remove accents before matching |
| `drunCache` | `$XDG_CACHE_HOME/line-launcher.druncache` | application/action history file |
| `commandAccent` | unset | accent used while the `>` provider is active |

Set `drunCache` to an absolute path or a filename relative to
`$XDG_CACHE_HOME`. Using `"rofi3.druncache"` shares application history with
Rofi because the file format is compatible.

## Colours and visual effects

When `colorsFile` is unset, the launcher probes these files in order:

| Path | Format |
| --- | --- |
| `$XDG_CACHE_HOME/wal/colors.json` | pywal |
| `$XDG_CACHE_HOME/wallust/colors.json` | wallust |
| `$XDG_CACHE_HOME/matugen/colors.json` | matugen |

The first readable file wins. For pywal and wallust, `accentKey = "auto"`
compares `color1` through `color6` with the foreground using CIEDE2000 and
chooses the most distinct colour. Matugen uses its named `primary`,
`on_surface`, and `error` roles instead.

The selected palette source, format, accent, and contrast measurement are
printed in the launcher log at startup.

There are two effects:

- The legibility glow uses the palette background beneath text and frame
  strokes, helping them survive bright wallpapers.
- The accent aura follows the selected result and typed query. During a
  confirmation it transitions to `colors.danger`.

Both radii scale with `fontSize`. Setting `glowEnabled = false` prevents both
effects from being constructed.

### Layout and animations

The launcher selects Hyprland's focused monitor, occupies a transparent layer
surface, and places only its visible content at the top centre. `topMargin`
controls its distance beneath a panel or clock.

The centre frame fades in while its whiskers drift into position over 90 ms.
Launching a result collapses the box to a line, sends the whiskers outward,
and flattens the result selection. Escape uses a shorter plain fade so
launching and cancelling remain visually distinct.

The selection outline and result lane animate together when navigating. With
`listPerspective = 0`, results form an evenly spaced straight list. Values up
to `1` progressively narrow and tilt lower rows into a receding fan. Result
opacity follows lane depth rather than distance from the selection.

## Command-line reference

```text
line-launcher [OPTIONS]
command-producing-lines | line-launcher [OPTIONS]
```

| Flag | Effect |
| --- | --- |
| `--toggle` | close the running launcher, or open it if absent |
| `--items N` | override the number of visible result rows |
| `--prompt TEXT` | set input placeholder text |
| `--config PATH` | use an alternate readable JSON configuration |
| `-n NAME`, `--namespace NAME` | set the layer-shell namespace |
| `-h`, `--help` | print usage information |

The default namespace is `line-launcher`. A custom namespace must also be used
in the compositor's layer rule:

```sh
line-launcher --namespace work-launcher
```

```lua
hl.layer_rule({
  match = { namespace = "work-launcher" },
  blur = true,
  ignore_alpha = 0.15,
})
```

## Files and state

| Path | Purpose |
| --- | --- |
| `/etc/xdg/line-launcher/config.json` | system configuration |
| `$XDG_CONFIG_HOME/line-launcher/config.json` | user configuration |
| `$XDG_CACHE_HOME/line-launcher.druncache` | application/action launch history |
| `$XDG_STATE_HOME/line-launcher/history.json` | shell-command history |

## Troubleshooting

### Win opens the launcher again instead of closing it

Make sure there is exactly one compositor binding and that it runs:

```sh
line-launcher --toggle
```

Do not separately bind Win to `qs kill`, `pkill`, or another close command.
The toggle must decide whether to open or close atomically.

### The shortcut says `unknown option: --toggle`

Hyprland is finding an older package. Check all available copies:

```sh
type -a line-launcher
line-launcher --help
```

Rebuild the Home Manager/NixOS configuration or use the stable Home Manager
profile path shown in the Hyprland setup section.

### The whole monitor is blurred

Verify that the rule matches namespace `line-launcher` and sets
`ignore_alpha = 0.15`. The surface is intentionally full-screen and mostly
transparent.

### Colours do not update

Check the startup log for the selected palette path and format. Confirm that
the JSON file exists and is readable. An explicit `colorsFile` disables all
automatic palette probing.

### Power actions do not run

The launcher runs the configured command; permissions are controlled by the
system. Test the same command in a terminal, for example:

```sh
systemctl reboot
```

### Inspect or close running instances

```sh
qs list --all
qs kill --path /path/to/line-launcher
```

## Development and tests

```sh
nix develop
./tests/run.sh
nix flake check
```

Run the checkout directly with:

```sh
qs -p .
```

## Credits

`rofi-search.js` is taken from
[wave-launcher](https://github.com/Kalkaro/wave-launcher) (MIT), which ports
the search, ranking, and history logic from
[Rofi](https://github.com/davatorium/rofi) (MIT). Both licences are reproduced
in [`licenses/`](licenses/).

Everything else is MIT licensed; see [LICENSE](LICENSE).
