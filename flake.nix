{
  description = "Compositor for the COSMIC desktop environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    parts.url = "github:hercules-ci/flake-parts";
    parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    crane.url = "github:ipetkov/crane";

    rust.url = "github:oxalica/rust-overlay";
    rust.inputs.nixpkgs.follows = "nixpkgs";

    nix-filter.url = "github:numtide/nix-filter";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      parts,
      crane,
      rust,
      nix-filter,
      ...
    }:
    parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        {
          self',
          lib,
          system,
          ...
        }:
        let
          pkgs = nixpkgs.legacyPackages.${system}.extend rust.overlays.default;
          rust-toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;
          craneArgs = {
            pname = "cosmic-comp";
            version = self.rev or "dirty";

            src = nix-filter.lib.filter {
              root = ./.;
              include = [
                ./src
                ./i18n.toml
                ./Cargo.toml
                ./Cargo.lock
                ./resources
                ./cosmic-comp-config
              ];
            };

            nativeBuildInputs = with pkgs; [
              pkg-config
              autoPatchelfHook
              cmake
            ];

            buildInputs = with pkgs; [
              wayland
              systemd # For libudev
              seatd # For libseat
              libxkbcommon
              libinput
              mesa # For libgbm
              fontconfig
              stdenv.cc.cc.lib
              pixman
              libdisplay-info
            ];

            runtimeDependencies = with pkgs; [
              libglvnd # For libEGL
              wayland # winit->wayland-sys wants to dlopen libwayland-egl.so
              # for running in X11
              xorg.libX11
              xorg.libXcursor
              xorg.libxcb
              xorg.libXi
              libxkbcommon
              # for vulkan backend
              vulkan-loader
            ];
          };

          cargoArtifacts = craneLib.buildDepsOnly craneArgs;
          cosmic-comp = craneLib.buildPackage (craneArgs // { inherit cargoArtifacts; });
        in
        {
          apps.cosmic-comp = {
            type = "app";
            program = lib.getExe self'.packages.default;
          };

          checks.cosmic-comp = cosmic-comp;
          packages.default = cosmic-comp;

          devShells.default = craneLib.devShell {
            LD_LIBRARY_PATH = lib.makeLibraryPath (
              __concatMap (d: d.runtimeDependencies) (__attrValues self'.checks)
            );

            inputsFrom = [ cosmic-comp ];

            # clippy and rustfmt are provided by the rust-overlay toolchain but listed
            # here explicitly so the devShell's capabilities are visible at a glance.
            packages = with pkgs; [
              rust-analyzer
              clippy
              rustfmt
            ];

            shellHook = ''
              echo ""
              echo "cosmic-comp-fork development shell"
              echo "  Rust $(rustc --version | cut -d' ' -f2)  |  $(cargo --version)"
              echo ""
              echo "Tier 1 (build):"
              echo "  cargo check             - type check (fastest feedback)"
              echo "  cargo build             - debug build"
              echo "  cargo build --release   - release build (for Tier 3 testing)"
              echo "  cargo clippy            - lint"
              echo ""
              echo "Tier 2 (nested winit):"
              echo "  COSMIC_BACKEND=winit ./target/debug/cosmic-comp"
              echo ""
              echo "Tier 3 reminder: copy release binary to /usr/local/bin/cosmic-comp-fork,"
              echo "  then test on the separate 'testcomp' user account (see SAFETY.md)"
              echo ""
            '';
          };
        };
    };
}
