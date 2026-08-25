{
  lib,
  stdenvNoCC,
  writeShellApplication,
  quickshell,
}: let
  # QML is interpreted, not compiled -- the "build" is a copy into the store.
  # Keeping it a separate derivation means the wrapper below can reference a
  # stable path without embedding the whole source tree in its script.
  qmlSource = stdenvNoCC.mkDerivation {
    pname = "line-launcher-qml";
    version = "0.1.0";

    # Only the QML sources and their qmldir belong in the store copy: no
    # flake, no nix/, no tests. Derived from the extensions rather than a
    # hand-kept list, so new components need no change here.
    src = lib.fileset.toSource {
      root = ../.;
      fileset =
        lib.fileset.difference
        (lib.fileset.fileFilter
          (file: file.hasExt "qml" || file.hasExt "js" || file.name == "qmldir")
          ../.)
        (lib.fileset.maybeMissing ../tests);
    };

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/line-launcher"
      cp -r ./. "$out/share/line-launcher/"
      runHook postInstall
    '';
  };

  # The shebang and `set` line are dropped: writeShellApplication supplies its
  # own, and a second copy would trip shellcheck.
  launcherBody =
    builtins.replaceStrings
    ["#!/usr/bin/env bash\n" "set -euo pipefail\n"]
    ["" ""]
    (builtins.readFile ../launcher.sh);
in
  writeShellApplication {
    name = "line-launcher";

    runtimeInputs = [quickshell];

    text =
      ''
        export LINE_LAUNCHER_QML_DIR="${qmlSource}/share/line-launcher"
      ''
      + launcherBody;

    meta = {
      description = "Wayland application launcher for Hyprland, written in Quickshell";
      homepage = "https://github.com/ilyanix/line-launcher";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "line-launcher";
    };
  }
