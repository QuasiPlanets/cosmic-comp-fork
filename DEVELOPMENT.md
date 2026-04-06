# Development Roadmap

This document tracks the phased development plan for cosmic-comp-fork. Each phase has clear goals, safety requirements, and completion criteria.

## Phase Overview

| Phase | Focus | Status |
|---|---|---|
| Phase 1 | Protocol extensions (new requests/events) | **Complete** |
| Phase 2 | Compositor-side handlers (implement operations in Shell) | Not started |
| Phase 3 | Integration testing with cosmic-layout-presets client | Not started |
| Phase 4 | Atomic batch operations (layout transactions) | Not started |

## Phase 1: Protocol Extensions

**Goal:** Define and implement new protocol requests and events in `zcosmic_toplevel_info` and `zcosmic_toplevel_manager`.

**Deliverables:**
- New events: `floating_state`, `stacking_order` in toplevel info
- New requests: `set_position`, `set_size`, `set_floating`, `set_tiled`, `set_stacking_order` in toplevel manager
- Updated ARCHITECTURE.md with protocol documentation
- Protocol XML definitions (approach TBD: fork cosmic-protocols or vendor)

**Safety gate:** `cargo check` passes, Tier 2 nested winit test with a simple client.

**Detailed plan:** See `.cursor/agents/Phase1-Protocol-Extension.md`.

### Phase 1 Summary (completed 2026-04-06)

**Approach:** Forked `cosmic-protocols` to [`QuasiPlanets/cosmic-protocols-fork`](https://github.com/QuasiPlanets/cosmic-protocols-fork) and extended the existing protocol XML with version-gated additions. The compositor uses the fork via a `[patch]` override in `Cargo.toml` pointing at the local clone at `/home/tes/cosmic-protocols-fork`.

**Protocol XML changes** (2 files in `cosmic-protocols-fork`):

- `unstable/cosmic-toplevel-management-unstable-v1.xml`:
  - Bumped `zcosmic_toplevel_manager_v1` interface version 4 -> 5
  - Added 5 new capability enum entries (since=5): `set_position` (9), `set_size` (10), `set_floating` (11), `set_tiled` (12), `set_stacking_order` (13)
  - Added 5 new requests (since=5): `set_position(toplevel, x, y)`, `set_size(toplevel, width, height)`, `set_floating(toplevel)`, `set_tiled(toplevel)`, `set_stacking_order(toplevel, order)`

- `unstable/cosmic-toplevel-info-unstable-v1.xml`:
  - Bumped `zcosmic_toplevel_info_v1` and `zcosmic_toplevel_handle_v1` interface versions 3 -> 4
  - Added state enum entries (since=4): `tiled` (value=5), `floating` (value=6)
  - Added new event (since=4): `stacking_order(order: uint)`

**Compositor changes** (5 files in `cosmic-comp-fork`):

| File | Change |
|---|---|
| `Cargo.toml` | `[patch]` section points `cosmic-protocols` and `cosmic-client-toolkit` at local fork |
| `src/state.rs` | 5 new capabilities advertised: `SetPosition`, `SetSize`, `SetFloating`, `SetTiled`, `SetStackingOrder` |
| `src/wayland/protocols/toplevel_management.rs` | Global version bumped 4 -> 5; 5 new trait methods with empty defaults; 5 new `Dispatch::request()` match arms using safe `if let Some(window)` |
| `src/wayland/handlers/toplevel_management.rs` | 5 new methods overridden on `State` with `tracing::debug!` logging (Phase 1 no-ops) |
| `src/wayland/protocols/toplevel_info.rs` | Global version bumped 3 -> 4; version-gated scaffolding for `tiled`/`floating` states and `stacking_order` event (not yet sent -- Phase 2) |

**Technical decisions:**

- All extensions are additive and version-gated. Clients binding older protocol versions are completely unaffected.
- No third-party crates added. No `unwrap()` or `panic!()` in new code.
- New dispatch arms use `if let Some(window) = window_from_handle(...)` for safe handle resolution.
- No `Window` trait changes -- tiled/floating state resolution deferred to Phase 2.
- `begin_layout_transaction` / `commit_layout_transaction` deferred to Phase 4.

**Verification:**

- `cargo check --features server` in `cosmic-protocols-fork`: PASS
- `cargo check` in `cosmic-comp-fork`: PASS
- `cargo clippy --all-features -- -D warnings` in `cosmic-comp-fork`: PASS (zero warnings)

**Branch:** `phase-1-protocol-extension` (XML changes in protocols fork are local only, not yet pushed to GitHub).

## Phase 2: Compositor-Side Handlers

**Goal:** Wire the new protocol requests through to actual window management operations in the Shell.

**Deliverables:**
- `set_position` moves floating windows via `FloatingLayout.space`
- `set_size` sends configure events and updates geometry
- `set_floating` / `set_tiled` moves windows between layouts via `Workspace`
- `set_stacking_order` reorders windows in the floating layer
- `floating_state` and `stacking_order` events sent on state changes

**Safety gate:** Tier 2 testing for protocol logic. Tier 3 (separate test user) for any changes touching rendering or input focus.

## Phase 3: Integration Testing

**Goal:** Verify end-to-end functionality with the `cosmic-layout-presets` client application.

**Deliverables:**
- Client can save a complete window layout (positions, sizes, tiled/floating state, stacking order)
- Client can restore a saved layout and all windows return to their exact positions
- Round-trip fidelity: save -> rearrange -> restore produces identical layout

**Safety gate:** Full Tier 3 testing on the separate test user account with real applications.

## Phase 4: Atomic Batch Operations

**Goal:** Implement a transaction mechanism so layout restore can be applied atomically.

**Deliverables:**
- `begin_layout_transaction` / `commit_layout_transaction` protocol requests
- Operations between begin/commit are queued and applied in a single frame
- Visual glitches from partial layout application are eliminated

**Safety gate:** Tier 3 testing with complex multi-window layouts.

## Build Commands

```bash
# Type checking (fastest feedback)
cargo check

# Debug build
cargo build

# Release build (for Tier 3 testing)
cargo build --release

# Lint
cargo clippy

# Run nested (Tier 2)
COSMIC_BACKEND=winit ./target/debug/cosmic-comp

# Copy for Tier 3 testing
sudo cp target/release/cosmic-comp /usr/local/bin/cosmic-comp-fork
```

## Safety Reminders

Before starting any phase:
1. Re-read [SAFETY.md](SAFETY.md)
2. Verify your test user account (`testcomp`) is set up and working
3. Confirm `cargo check` passes on the unmodified code
4. Check that nested winit testing works with the unmodified compositor

Between phases:
1. Commit all changes with descriptive messages
2. Verify the master branch still builds cleanly
3. Run Tier 3 testing for the completed phase before starting the next
4. Update ARCHITECTURE.md with any new findings or changes

## Nix Development Environment

This project includes a Nix flake (`flake.nix`) that provides a fully reproducible
development shell with pinned Rust (1.90), all C library dependencies, and
development tools (rust-analyzer, clippy, rustfmt).

**`nix develop` is the recommended way to enter the development environment.**
It guarantees every contributor has identical toolchain versions and native
library paths, eliminating "works on my machine" issues.

### Entering the Shell

```bash
nix develop
```

This gives you cargo, rustc, clippy, rustfmt, rust-analyzer, and all native
libraries (wayland, libinput, libseat, mesa, vulkan, etc.) without polluting
your system.

For automatic shell activation with direnv:

```bash
echo "use flake" > .envrc
direnv allow
```

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

```bash
nix build
```

The result is in `./result/bin/cosmic-comp`. This binary has correct RPATH
entries and can run outside `nix develop` without setting `LD_LIBRARY_PATH`.

## Development Workflow

All development happens on your main user account inside the Nix shell. Testing
is tiered by risk level.

### Tier 1: Build (zero risk)

All coding, type checking, and linting happens inside `nix develop`. This never
runs the compositor and cannot affect your session.

```bash
nix develop
cargo check            # fast type checking
cargo build            # debug build
cargo clippy           # lint
cargo build --release  # optimized build for Tier 3
```

### Tier 2: Quick Testing (low risk)

Run the compositor nested inside your existing Wayland session using the winit
backend. Good for smoke tests and protocol verification. If it crashes, only the
nested window closes -- your session is unaffected.

```bash
COSMIC_BACKEND=winit ./target/debug/cosmic-comp
```

Point test clients at the nested compositor's socket:

```bash
WAYLAND_DISPLAY=wayland-1 your-test-client
```

### Tier 3: Full Session Testing (placeholder)

To be set up later using either a separate test user account on a different TTY
or a virtual machine. See [SAFETY.md](SAFETY.md) for details.

### Reminder

**Never run an untested compositor as your daily driver.** Your main account's
session compositor must always be the stable, upstream binary. All real session
testing happens in isolated environments.

## Archive Log

- **2026-04-06**: Archived Nix dev environment setup plan to `.cursor/plans-archive/nix-dev-environment-setup.md`.
- **2026-04-06**: Created Phase 1 sub-agent definition at `.cursor/agents/Phase1-Protocol-Extension.md`. See also [AGENTS.md](AGENTS.md).
- **2026-04-06**: Phase 1 Protocol Extension complete. Archived plan to `.cursor/plans-archive/phase-1-protocol-extension.md`. Correcting protocols fork to use official remote `git@github.com:QuasiPlanets/cosmic-protocols-fork.git`.
