---
name: Nix dev environment enhancement
overview: Enhance the existing upstream flake.nix devShell with development tools and a shell hook, append Nix workflow documentation to DEVELOPMENT.md, and add .direnv to .gitignore.
todos:
  - id: enhance-flake
    content: Add rust-analyzer, clippy, rustfmt to packages and an informative shellHook to devShells.default in flake.nix
    status: completed
  - id: dev-docs
    content: Append Nix Development Environment section to DEVELOPMENT.md
    status: in_progress
  - id: gitignore-nix
    content: Append .direnv to .gitignore
    status: completed
isProject: false
---

# Enhance Existing Nix Development Environment

## Key Finding: Upstream Already Has a Complete Flake

The existing `[flake.nix](flake.nix)` is already production-ready and well-structured:

- **rust-overlay** (oxalica) for the Rust toolchain, reading from `[rust-toolchain.toml](rust-toolchain.toml)` which pins Rust **1.90** with `rust-src`
- **crane** for reproducible Cargo builds with dependency caching
- **flake-parts** for multi-system support (x86_64-linux, aarch64-linux)
- **nix-filter** for clean source filtering
- All necessary **build dependencies** already present: `pkg-config`, `cmake`, `wayland`, `systemd` (udev), `seatd` (libseat), `libinput`, `mesa` (gbm), `libxkbcommon`, `fontconfig`, `pixman`, `libdisplay-info`
- All necessary **runtime dependencies** already present: `libglvnd` (EGL), `wayland`, X11 libs, `vulkan-loader`
- A `devShells.default` that inherits all build inputs and sets `LD_LIBRARY_PATH`

**We should NOT rewrite this flake.** Instead, we make three targeted enhancements.

## Changes

### 1. Enhance `devShells.default` in `[flake.nix](flake.nix)`

Add to the existing `devShell` block (lines 106-113):

- **Extra packages**: `rust-analyzer`, `clippy`, and `rustfmt` -- listed explicitly in `packages` for self-documentation even though clippy and rustfmt are technically provided by the rust-overlay toolchain. This makes the devShell's capabilities immediately visible to anyone reading the flake.
- **Shell hook**: Print an informative banner covering Tier 1 build commands, Tier 2 nested winit testing, and a Tier 3 reminder about the separate test user.

The change is minimal -- we add `packages` and `shellHook` to the existing `craneLib.devShell` call:

```nix
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
```

Note: `clippy` and `rustfmt` are already provided by `rust-bin.fromRustupToolchainFile` via the rust-overlay (they are default rustup components). Listing them explicitly in `packages` is redundant at the Nix level but serves as self-documentation -- anyone reading the flake immediately sees all available dev tools without needing to know rust-overlay internals.

### 2. Append Nix section to `[DEVELOPMENT.md](DEVELOPMENT.md)`

Append a new section **after** line 97 (end of file), following append-only policy:

```markdown
## Nix Development Environment

This project includes a Nix flake (`flake.nix`) that provides a fully reproducible
development shell with pinned Rust (1.90), all C library dependencies, and
development tools (rust-analyzer, clippy, rustfmt).

**`nix develop` is the recommended way to enter the development environment.**
It guarantees every contributor has identical toolchain versions and native
library paths, eliminating "works on my machine" issues.

### Entering the Shell

    nix develop

This gives you cargo, rustc, clippy, rustfmt, rust-analyzer, and all native
libraries (wayland, libinput, libseat, mesa, vulkan, etc.) without polluting
your system.

For automatic shell activation with direnv:

    echo "use flake" > .envrc
    direnv allow

### Building Inside the Shell

All build commands from the "Build Commands" section above work inside `nix develop`.
The Nix shell sets `LD_LIBRARY_PATH` for runtime dependencies (EGL, Vulkan,
Wayland, X11) so nested winit testing works directly.

### How Nix Fits the Three-Tier Testing Strategy

Nix is the foundation for Tier 1 and Tier 2. Tier 3 uses the release binary
produced inside the Nix shell but runs outside it on a separate user account.

- **Tier 1 (Build)**: `nix develop` then `cargo check` / `cargo build`. Fully
  reproducible environment. This is the primary development workflow.
- **Tier 2 (Nested winit)**: Inside `nix develop`, run
  `COSMIC_BACKEND=winit ./target/debug/cosmic-comp`. The `LD_LIBRARY_PATH` set
  by the shell ensures all runtime libraries (EGL, Vulkan, Wayland) are found.
  Crashes only affect the nested window, not your session.
- **Tier 3 (Separate test user)**: Build with `cargo build --release` inside
  `nix develop`, then copy the binary for the test user:
  `sudo cp target/release/cosmic-comp /usr/local/bin/cosmic-comp-fork`.
  Switch to TTY3, log in as `testcomp`, and launch the compositor with real
  hardware. Note: a `cargo build` binary may need `LD_LIBRARY_PATH` set on
  the target user; alternatively, use `nix build` which produces a fully
  patched binary via `autoPatchelfHook`.

### Nix Build (fully hermetic)

To build the compositor entirely through Nix (no manual cargo):

    nix build

The result is in `./result/bin/cosmic-comp`. This binary has correct RPATH
entries and can run outside `nix develop` without setting `LD_LIBRARY_PATH`.
```

### 3. Update `[.gitignore](.gitignore)`

Append after the existing `.cursor/` block:

```gitignore
# Nix
.direnv
```

The `/result` entry already exists on line 16. The `flake.nix` and `flake.lock` are not in `.gitignore` and will remain tracked (correct behavior).