{
  description = "line-launcher - a Wayland application launcher for Hyprland, written in Quickshell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    # Taken from upstream rather than nixpkgs: the nixpkgs copy lags behind.
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    quickshell,
  }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
    ] (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      quickshellPkg = quickshell.packages.${system}.default;

      line-launcher = pkgs.callPackage ./nix/package.nix {
        quickshell = quickshellPkg;
      };
    in {
      packages = {
        default = line-launcher;
        inherit line-launcher;
      };

      apps.default = {
        type = "app";
        program = "${line-launcher}/bin/line-launcher";
        meta.description = "Run line-launcher";
      };

      devShells.default = pkgs.mkShell {
        # `nix develop` then `qs -p .` runs the launcher straight from the
        # checkout, with no install step and no rebuild between edits.
        packages = [
          quickshellPkg
          pkgs.qt6.qtbase
          pkgs.qt6.qtdeclarative # also carries qmlls, qmllint and qmlformat
          pkgs.qt6.qtsvg
          pkgs.qt6.qtimageformats
          pkgs.shellcheck
          pkgs.alejandra
          # tests/run.sh renders the glow suite against this: the offscreen
          # platform falls back to the software renderer, where every
          # ShaderEffect is a no-op.
          pkgs.xorg.xvfb
          # tests/run.sh compares the two rendered previews with this, to
          # prove the halos reached the glass rather than merely existing.
          pkgs.imagemagick
        ];

        shellHook = ''
          # qmlls needs to be told where the Quickshell modules live, both
          # through the environment and through the .qmlls.ini it looks for
          # next to the sources. The file is gitignored.
          export QML_IMPORT_PATH="${quickshellPkg}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
          export QML2_IMPORT_PATH="$QML_IMPORT_PATH"

          # Replace the generated file atomically, including stale VFS symlinks.
          qmlls_config_tmp=$(mktemp .qmlls.ini.XXXXXX)
          cat > "$qmlls_config_tmp" <<EOF
          [General]
          buildDir=.
          importPaths=${quickshellPkg}/lib/qt-6/qml:${pkgs.qt6.qtdeclarative}/lib/qt-6/qml
          EOF
          sed -i 's/^ *//' "$qmlls_config_tmp"
          mv -f -- "$qmlls_config_tmp" .qmlls.ini

          echo "line-launcher dev shell"
          echo "  qs -p .          run the launcher from this checkout"
          echo "  ./tests/run.sh   headless assertions"
        '';
      };

      formatter = pkgs.alejandra;
    })
    // {
      homeManagerModules.default = import ./nix/hm-module.nix self;
      homeManagerModules.line-launcher = self.homeManagerModules.default;

      nixosModules.default = import ./nix/nixos-module.nix self;
      nixosModules.line-launcher = self.nixosModules.default;
    };
}
