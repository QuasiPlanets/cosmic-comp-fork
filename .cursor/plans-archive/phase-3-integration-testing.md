---
name: Phase 3 Integration Testing
overview: Update the cosmic-layout-presets client to consume the new compositor protocol extensions (Phase 1-2), then verify end-to-end layout save/restore fidelity with real windows.
todos:
  - id: p3-client-deps
    content: Update Cargo.toml in the existing local client directory (/home/tes/QuasiPlanetsRepos/cosmic-layout-presets) to point at our cosmic-protocols-fork via [patch] section, then run cargo check to verify the new protocol types are available
    status: completed
  - id: p3-action-variants
    content: Add 5 new ToplevelAction variants and handle_toplevel_action match arms in wayland_handler.rs
    status: completed
  - id: p3-capture-update
    content: Update capture_toplevels to use real tiled/floating state and stacking_order from protocol events
    status: completed
  - id: p3-apply-update
    content: Update apply pipeline to use SetPosition, SetSize, SetFloating, SetTiled, SetStackingOrder instead of workarounds
    status: completed
  - id: p3-info-events
    content: Verify ToplevelInfoHandler receives new state flags and stacking_order event correctly
    status: completed
  - id: p3-verify
    content: cargo check + clippy + Tier 2 end-to-end test (capture -> rearrange -> apply -> verify)
    status: completed
isProject: false
---

# Phase 3: Integration Testing with cosmic-layout-presets

## Pre-Work: Re-Read All Project Documents

Before any code changes, the implementer must re-read in full:

- [ARCHITECTURE.md](https://github.com/QuasiPlanets/cosmic-comp-fork/blob/phase-1-protocol-extension/ARCHITECTURE.md) (especially the "Client Requirements -- cosmic-layout-presets" section, the Gap Table, and the "Extension Targets" table)
- [DEVELOPMENT.md](https://github.com/QuasiPlanets/cosmic-comp-fork/blob/phase-1-protocol-extension/DEVELOPMENT.md) (especially the Phase 2 Summary for exact details of what Shell methods exist and how info state sending works)
- [SAFETY.md](https://github.com/QuasiPlanets/cosmic-comp-fork/blob/phase-1-protocol-extension/SAFETY.md)
- [.cursor/rules/core-enforcement.mdc](https://github.com/QuasiPlanets/cosmic-comp-fork/blob/phase-1-protocol-extension/.cursor/rules/core-enforcement.mdc) (all rules, including Archive Rule and one-todo-at-a-time)

If any clarification is needed about Phase 1 or Phase 2 decisions, ask the existing Phase1-Protocol-Extension sub-agent (agent ID `22fb0a47-5ddc-41ba-b032-1de309d79441`) or Phase2-Shell-Implementation sub-agent (agent ID `422b88d1-42de-48cd-8ede-7812a7533d9e`).

## Dependency Rule

No third-party crates will be added. All changes use only official cosmic-layout-presets, cosmic-protocols, and cctk code.

## Goal

Update the `cosmic-layout-presets` client application to use the new compositor protocol features (Phases 1-2), replacing heuristic workarounds with precise protocol requests, and verify end-to-end layout save/restore fidelity.

Phase 3 is **client-side work only** -- no compositor changes. The compositor (cosmic-comp-fork) is ready.

## Working directories (this machine)

- **Client working directory (use this clone only; do not `git clone` the client again):** `/home/tes/QuasiPlanetsRepos/cosmic-layout-presets`
- **Compositor** (read-only in Phase 3; build/run Tier 2 tests from here): `/home/tes/cosmic-comp-fork`

Upstream / reference URLs: [cosmic-layout-presets](https://github.com/QuasiPlanets/cosmic-layout-presets), [cosmic-comp-fork](https://github.com/QuasiPlanets/cosmic-comp-fork) (branch `phase-1-protocol-extension`), [cosmic-protocols-fork](https://github.com/QuasiPlanets/cosmic-protocols-fork).

## Two Repositories

- **Compositor** (read-only in Phase 3): local `/home/tes/cosmic-comp-fork` — [QuasiPlanets/cosmic-comp-fork](https://github.com/QuasiPlanets/cosmic-comp-fork) (branch `phase-1-protocol-extension`) -- already complete, no modifications
- **Protocols fork** (read-only in Phase 3): [QuasiPlanets/cosmic-protocols-fork](https://github.com/QuasiPlanets/cosmic-protocols-fork) -- already extended with Phase 1 XML
- **Client** (modified in Phase 3): local `/home/tes/QuasiPlanetsRepos/cosmic-layout-presets` — [QuasiPlanets/cosmic-layout-presets](https://github.com/QuasiPlanets/cosmic-layout-presets)

## Current Client State (what we build on)

The client currently:

- **Captures**: app_id, title, workspace, x, y, width, height, `state` (string: "Maximized" / "Fullscreen" / "Minimized" / "Floating"), `stack_order` (activation-based rank, not true z-order)
- **Restores**: workspace, maximize/minimize/fullscreen states, activation order. Position, size, tiled/floating, and z-order are **not restored** (captured but discarded on apply)
- **Workarounds**: 2-pass `UnsetMaximized`/`UnsetMinimized` for floating mismatch, `Activate` in `stack_order` order for z-order proxy, 3s post-launch wait, 125ms polling

Key client files (under `/home/tes/QuasiPlanetsRepos/cosmic-layout-presets`; line numbers are approximate — verify in tree):

- `src/wayland_handler.rs` -- `ToplevelAction` enum, `handle_toplevel_action` dispatch, `ToplevelInfoHandler` implementation
- `src/preset_session.rs` -- `capture_toplevels`, `apply_minimize_and_restore`, `replay_preset_activation_order`, `repeat_unset_sequence_for_floating_or_fullscreen_mismatch`
- `src/config.rs` -- `WindowEntry` struct: `state: String`, `stack_order: u32`
- `Cargo.toml` -- `cctk` and `cosmic-protocols` at upstream `rev = "d0e95be"` until patched

GitHub mirror for browsing: [cosmic-layout-presets](https://github.com/QuasiPlanets/cosmic-layout-presets).

## Implementation Plan

### Part A: Point Client at Protocol Fork

In `**/home/tes/QuasiPlanetsRepos/cosmic-layout-presets`**, update `Cargo.toml` to use our `cosmic-protocols-fork` instead of upstream. Use a `[patch]` section (matching the pattern in cosmic-comp-fork). Reference: [Cargo.toml on GitHub](https://github.com/QuasiPlanets/cosmic-layout-presets/blob/main/Cargo.toml).

```toml
[patch.'https://github.com/pop-os/cosmic-protocols']
cosmic-protocols = { git = "https://github.com/QuasiPlanets/cosmic-protocols-fork.git", branch = "main" }
cosmic-client-toolkit = { git = "https://github.com/QuasiPlanets/cosmic-protocols-fork.git", branch = "main" }
```

Run `cargo check` in `/home/tes/QuasiPlanetsRepos/cosmic-layout-presets` to verify the new protocol types are available.

### Part B: Add New ToplevelAction Variants

In `**/home/tes/QuasiPlanetsRepos/cosmic-layout-presets/src/wayland_handler.rs**` (see [GitHub](https://github.com/QuasiPlanets/cosmic-layout-presets/blob/main/src/wayland_handler.rs)), extend the `ToplevelAction` enum with 5 new variants:

```rust
SetPosition(ExtForeignToplevelHandleV1, i32, i32),
SetSize(ExtForeignToplevelHandleV1, i32, i32),
SetFloating(ExtForeignToplevelHandleV1),
SetTiled(ExtForeignToplevelHandleV1),
SetStackingOrder(ExtForeignToplevelHandleV1, u32),
```

Add corresponding match arms in `handle_toplevel_action` that resolve the cosmic handle via `state.cosmic_toplevel(&handle)` and call the new `manager` methods (e.g., `manager.set_position(&cosmic_handle, x, y)`). Follow the exact pattern of existing arms like `Activate` and `MoveToWorkspace`.

**Important**: The exact method names on `manager` depend on how `cctk` exposes the new protocol requests. Read the generated code in `cosmic-protocols-fork/client-toolkit/` to find the correct method signatures.

### Part C: Update Capture to Use Real Protocol Data

In `**/home/tes/QuasiPlanetsRepos/cosmic-layout-presets/src/preset_session.rs`** (see [GitHub](https://github.com/QuasiPlanets/cosmic-layout-presets/blob/main/src/preset_session.rs)), update `capture_toplevels`:

1. **Tiled/floating state**: The compositor now sends `Tiled` and `Floating` state flags via `zcosmic_toplevel_handle_v1`. Check `ToplevelInfo.state` for these new flags. Update the `state` derivation (currently lines 432-441) to distinguish `"Tiled"` vs `"Floating"` instead of defaulting everything to `"Floating"`.
2. **Stacking order**: The compositor now sends `stacking_order` events. If `ToplevelInfo` exposes a `stacking_order` field (check cctk's `ToplevelInfo` struct), use it directly instead of the activation-history-based `raw_seq` ranking.

**Data model change** in `**/home/tes/QuasiPlanetsRepos/cosmic-layout-presets/src/config.rs`** (see [GitHub](https://github.com/QuasiPlanets/cosmic-layout-presets/blob/main/src/config.rs)): The `WindowEntry.state` field is a `String`. Consider whether to add a separate `is_tiled: bool` field or use the string values `"Tiled"` / `"Floating"`. The simplest approach is to keep the string representation and add `"Tiled"` as a new value, since the existing code already matches on state strings.

### Part D: Update Apply to Use New Protocol Requests

This is the core integration step. In `**/home/tes/QuasiPlanetsRepos/cosmic-layout-presets/src/preset_session.rs`**, update the apply pipeline:

1. **Replace floating workaround**: Instead of `repeat_unset_sequence_for_floating_or_fullscreen_mismatch` (2-pass `UnsetMaximized`/`UnsetMinimized`), send `SetFloating(handle)` or `SetTiled(handle)` directly based on `entry.state`.
2. **Restore position and size**: After setting tiled/floating state and workspace, send `SetPosition(handle, entry.x, entry.y)` and `SetSize(handle, entry.width as i32, entry.height as i32)` for floating windows. Currently these are captured but discarded (logged as non-restorable at lines 868-871).
3. **Restore stacking order**: Replace or supplement `replay_preset_activation_order` (which uses `Activate` as a z-order proxy) with `SetStackingOrder(handle, entry.stack_order)`. The client should send these in ascending `stack_order` order so the compositor raises windows correctly.
4. **Apply ordering**: The recommended sequence per window is:
  - Move to correct workspace (`MoveToWorkspace`)
  - Set tiled/floating state (`SetFloating` or `SetTiled`)
  - Set position and size (`SetPosition`, `SetSize`) -- floating only
  - Set stacking order (`SetStackingOrder`) -- floating only, after all windows positioned
5. **Simplify timing workarounds**: With direct protocol support, the 2-pass unset and some of the heuristic delays may be reducible. However, do NOT remove them entirely in Phase 3 -- keep them as fallbacks but prefer the new protocol requests. Full cleanup can happen after Phase 4 (transactions).

**Important**: Keep existing workarounds (`repeat_unset_sequence_for_floating_or_fullscreen_mismatch`, activation replay delay, `APPLY_POST_LAUNCH_WAIT_MAX`) as fallbacks until Phase 4 atomic transactions are implemented. The new protocol requests should be preferred when available, but the old paths must remain functional for graceful degradation.

### Part E: Handle New Info Events (ToplevelInfoHandler)

In `**/home/tes/QuasiPlanetsRepos/cosmic-layout-presets/src/wayland_handler.rs`**, verify that the `ToplevelInfoHandler` implementation for `AppData` correctly receives and propagates the new `Tiled`/`Floating` state flags and `stacking_order` event through `WaylandUpdate::Toplevel(Update)`.

Check `cctk`'s `ToplevelInfo` struct to see if the new state flags and stacking_order are already exposed or need explicit handling. If `cctk` automatically includes new `State` enum variants, the client may receive them with no code changes here -- just verify.

### Part F: Verify

1. `cargo check` passes in `/home/tes/QuasiPlanetsRepos/cosmic-layout-presets`
2. `cargo clippy -- -D warnings` clean (in the client directory)
3. **Tier 2 end-to-end test** (use existing local clones; do **not** `git clone` the client):
  - Build compositor: `cd /home/tes/cosmic-comp-fork && cargo build`
  - Start nested compositor: `cd /home/tes/cosmic-comp-fork && COSMIC_BACKEND=winit ./target/debug/cosmic-comp`
  - Build client: `cd /home/tes/QuasiPlanetsRepos/cosmic-layout-presets && cargo build`
  - Point client at nested compositor: `cd /home/tes/QuasiPlanetsRepos/cosmic-layout-presets && WAYLAND_DISPLAY=wayland-1 ./target/debug/cosmic-layout-presets`
  - Open several test windows in the nested compositor
  - Capture a preset
  - Rearrange windows (move, resize, toggle tiled/floating)
  - Apply the preset
  - Verify windows return to captured positions, sizes, tiled/floating state, and stacking order

## Files to Modify (client only)


| File                     | Change                                                                                                                        |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `Cargo.toml`             | `[patch]` section pointing cctk and cosmic-protocols at our fork                                                              |
| `src/wayland_handler.rs` | 5 new `ToplevelAction` variants + match arms in `handle_toplevel_action`                                                      |
| `src/config.rs`          | Possibly add `"Tiled"` state value handling to `WindowEntry`                                                                  |
| `src/preset_session.rs`  | Update `capture_toplevels` (real tiled/floating + stacking_order), update apply pipeline (new requests), simplify workarounds |


Files **not** modified: anything in [cosmic-comp-fork](https://github.com/QuasiPlanets/cosmic-comp-fork) (compositor is complete), protocol XML (no protocol changes in Phase 3).

## Safety and Testing

- **Tier 1 (Build):** `cargo check` + `cargo clippy` after each step. Required.
- **Tier 2 (Nested winit):** Required. Run compositor in nested winit, point client at it, verify capture and apply work.
- **Tier 3 (Separate test user):** Recommended for final validation with real KMS/DRM and real applications (multiple workspaces, mixed tiled/floating windows, multi-monitor if available).
- **No `unwrap()` or `panic!`** in new client code. Use `if let` / `eprintln!` for error cases.
- **Backward compatibility:** Client should gracefully fall back if the compositor does not advertise the new capabilities (check capabilities before sending new requests).
- **Keep existing workarounds as fallbacks** until Phase 4 transactions are available.

## Open Questions / Design Decisions

1. **cctk method names**: The exact Rust method signatures for the new manager requests depend on how `cctk` code-generates from the protocol XML. The implementer must read the generated code in [cosmic-protocols-fork/client-toolkit/](https://github.com/QuasiPlanets/cosmic-protocols-fork/tree/main/client-toolkit) to find the correct names.
2. **stacking_order in ToplevelInfo**: Does `cctk` automatically expose the new `stacking_order` event as a field on `ToplevelInfo`, or does it need explicit handler code? Must be checked during implementation.
3. **WindowEntry.state for tiled**: Should `"Tiled"` be a new string value alongside `"Floating"`, `"Maximized"`, etc.? Or add a separate `is_tiled: bool`? Recommend: use `"Tiled"` as a new state string for simplicity and backward compatibility with existing preset files (old presets without `"Tiled"` default to `"Floating"` behavior).
4. **Apply ordering and timing**: Should `SetPosition`/`SetSize` be sent immediately after `SetFloating`, or wait for a configure ack? The compositor processes requests sequentially on the same client connection, so immediate send should be fine. Test in Tier 2.

Final design decisions will be made during implementation, with input from the Phase1 or Phase2 sub-agents if clarification is needed.

## Success Criteria

- Client captures presets with real `Tiled`/`Floating` state (not inferred)
- Client captures presets with real `stacking_order` (not activation-based proxy)
- Client restores exact position and size for floating windows
- Client restores tiled/floating state reliably
- Client restores stacking order for floating windows
- Round-trip fidelity: capture -> rearrange -> apply produces identical layout
- Existing preset files continue to work (backward compatible)
- `cargo clippy -- -D warnings` clean
- No compositor modifications

## Archive Rule

After this plan is approved and implemented, the **main agent** (not the implementer sub-agent) will:

1. Copy this plan to `.cursor/plans-archive/phase-3-integration-testing.md` per the Archive Rule in `[.cursor/rules/core-enforcement.mdc](https://github.com/QuasiPlanets/cosmic-comp-fork/blob/phase-1-protocol-extension/.cursor/rules/core-enforcement.mdc)`.
2. Update `DEVELOPMENT.md` (append-only) to note the archival and Phase 3 completion status.

