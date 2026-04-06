# Phase 1 Sub-Agent: Protocol Extension

## Pre-Work: Re-Read All Project Documents

Before any code changes, re-read in full:

- [README.md](../../README.md)
- [SAFETY.md](../../SAFETY.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md) (especially the "Client Requirements -- cosmic-layout-presets" section)
- [DEVELOPMENT.md](../../DEVELOPMENT.md)
- [.cursor/rules/core-enforcement.mdc](../rules/core-enforcement.mdc)

## Objective

Add new Wayland protocol surface (requests, events, capabilities, dispatch) to cosmic-comp-fork so that the compositor can receive layout management requests and send new state events to clients. Phase 1 is **scaffolding only** -- no actual Shell operations (those are Phase 2).

## Dependency Rule

No third-party crates will be added. All changes use only official cosmic-comp, Smithay, and cosmic-protocols code.

## Scope and Boundaries

### In scope (Phase 1)

- Fork `cosmic-protocols` to `QuasiPlanets/cosmic-protocols-fork`
- Extend protocol XML: new requests (version bump manager v4 -> v5), new state values and event (info version bump v3 -> v4)
- Update `Cargo.toml` to point at our protocols fork
- Extend `ToplevelManagementHandler` trait with new methods (empty defaults)
- Add dispatch match arms for new request variants
- Advertise new capabilities in `state.rs`
- Override new methods on `State` with `tracing::debug!` logging
- Add version-gated scaffolding in `toplevel_info.rs` for new state values (not yet sent)

### Out of scope (deferred)

- Any `Window` trait changes -- deferred to Phase 2
- Tiled/floating state resolution (querying Shell or caching on surface) -- deferred to Phase 2
- `begin_layout_transaction` / `commit_layout_transaction` -- deferred to Phase 4
- Shell-side implementation of any request (set_position, set_size, etc.) -- deferred to Phase 2
- Files outside the protocol layer (no changes to `src/shell/`, `src/shell/layout/`, `src/shell/workspace.rs`)

## New Protocol Additions

### zcosmic_toplevel_manager_v1: New Requests (version 5)

| Request              | Parameters                                                              | Phase 1 behavior                              |
| -------------------- | ----------------------------------------------------------------------- | --------------------------------------------- |
| `set_position`       | `toplevel: zcosmic_toplevel_handle_v1`, `x: int32`, `y: int32`          | Log + no-op (Shell implementation in Phase 2) |
| `set_size`           | `toplevel: zcosmic_toplevel_handle_v1`, `width: int32`, `height: int32` | Log + no-op                                   |
| `set_floating`       | `toplevel: zcosmic_toplevel_handle_v1`                                  | Log + no-op                                   |
| `set_tiled`          | `toplevel: zcosmic_toplevel_handle_v1`                                  | Log + no-op                                   |
| `set_stacking_order` | `toplevel: zcosmic_toplevel_handle_v1`, `order: uint32`                 | Log + no-op                                   |

New capabilities to advertise: `SetPosition`, `SetSize`, `SetFloating`, `SetTiled`, `SetStackingOrder`.

### zcosmic_toplevel_handle_v1: New State Values (info version 4)

| State value | Meaning                          | Phase 1 behavior                            |
| ----------- | -------------------------------- | ------------------------------------------- |
| `tiled`     | Window is in the tiling layout   | Not yet sent (Phase 2 will query Workspace) |
| `floating`  | Window is in the floating layout | Not yet sent                                |

### zcosmic_toplevel_handle_v1: New Event

| Event            | Data            | Phase 1 behavior                                        |
| ---------------- | --------------- | ------------------------------------------------------- |
| `stacking_order` | `order: uint32` | Not yet sent (Phase 2 will read FloatingLayout z-order) |

## Architectural Note: Tiled/Floating State

Phase 1 will add scaffolding only. The decision on whether to add `is_tiled()`/`is_floating()` to the Window trait or query the Shell during the refresh cycle is deferred to Phase 2 implementation. No `Window` trait changes in Phase 1.

## Files to Modify (Phase 1 only)

| File | Change |
| --- | --- |
| External: `cosmic-protocols` fork | New requests, state values, event, capabilities in protocol XML |
| `Cargo.toml` | Point `cosmic-protocols` dependency and `[patch]` at our fork |
| `src/wayland/protocols/toplevel_management.rs` | New methods on `ToplevelManagementHandler` (empty defaults); new match arms in `Dispatch::request()` |
| `src/wayland/handlers/toplevel_management.rs` | Override new methods on `State` with `tracing::debug!` logging |
| `src/state.rs` | Add new capabilities to `vec![...]` |
| `src/wayland/protocols/toplevel_info.rs` | Version-gated scaffolding for new state values and `stacking_order` event (not yet sent) |

Files **not** modified in Phase 1: `src/wayland/handlers/toplevel_info.rs`, anything under `src/shell/`.

## Implementation Steps (ordered)

### Step 1: Fork and extend cosmic-protocols

1. Fork `pop-os/cosmic-protocols` to `QuasiPlanets/cosmic-protocols-fork`
2. Add new request opcodes to `zcosmic_toplevel_manager_v1` XML (version bump 4 -> 5)
3. Add new state enum values (`tiled`, `floating`) to `zcosmic_toplevel_handle_v1`
4. Add new `stacking_order` event to `zcosmic_toplevel_handle_v1`
5. Add new capability enum values (`SetPosition`, `SetSize`, `SetFloating`, `SetTiled`, `SetStackingOrder`)
6. Verify `cargo build` passes in the cosmic-protocols crate

### Step 2: Point cosmic-comp-fork at our protocol fork

1. Update `Cargo.toml` dependency and `[patch]` section to reference `QuasiPlanets/cosmic-protocols-fork`
2. Run `cargo update -p cosmic-protocols` to refresh the lockfile
3. Verify `cargo check` passes (new types are available but unused)

### Step 3: Extend ToplevelManagementHandler trait

In `src/wayland/protocols/toplevel_management.rs`:

1. Add new methods with empty default bodies:
   - `fn set_position(&mut self, dh, window, x: i32, y: i32) {}`
   - `fn set_size(&mut self, dh, window, width: i32, height: i32) {}`
   - `fn set_floating(&mut self, dh, window) {}`
   - `fn set_tiled(&mut self, dh, window) {}`
   - `fn set_stacking_order(&mut self, dh, window, order: u32) {}`
2. Add match arms in `Dispatch::request()` for new `Request` variants, calling the corresponding trait methods. Must handle these BEFORE the `_ => unreachable!()` arm.

### Step 4: Advertise new capabilities

In `src/state.rs`, append the new capability variants to the existing `vec![...]`.

### Step 5: Implement logging handlers

In `src/wayland/handlers/toplevel_management.rs`, override each new method with `tracing::debug!` logging (matching the pattern of existing handlers like `activate`, `close`, etc.).

### Step 6: Prepare toplevel_info for new state

In `src/wayland/protocols/toplevel_info.rs`, add version-gated scaffolding in `send_toplevel_to_client` for the new `tiled`/`floating` states and `stacking_order` event. Initially these will not fire (Phase 2 provides the data).

### Step 7: Verify

1. `cargo check` passes
2. `cargo clippy --all-features -- -D warnings` clean
3. `COSMIC_BACKEND=winit ./target/debug/cosmic-comp` starts and runs
4. Existing window management behavior is completely unchanged

## Safety and Testing

- **Tier 1 (Build):** `cargo check` + `cargo clippy` after each step. Required.
- **Tier 2 (Nested winit):** After Step 7, verify the compositor starts and existing window operations work. Required.
- **Tier 3 (Separate test user):** Not required for Phase 1 (no rendering, input, or session changes -- only protocol dispatch scaffolding).
- **No `unwrap()` or `panic!`** in new code. Use `tracing::warn!` for invalid requests.
- **No behavior changes** for existing clients. Phase 1 is scaffolding only.

## Backward Compatibility

- New requests are version-gated (version 5). Clients binding version 4 never see them.
- New state values in toplevel_info are version-gated (version 4). Clients binding version 3 are unaffected.
- New capabilities are additive. Clients that don't understand them ignore them per protocol convention.
- The `_ => unreachable!()` in current dispatch MUST be updated to handle new request variants.

## Success Criteria

- [ ] `cosmic-protocols-fork` exists with extended XML and builds
- [ ] `Cargo.toml` points at our fork; `cargo check` passes
- [ ] New `ToplevelManagementHandler` methods exist with empty defaults
- [ ] New request variants dispatched in `Dispatch::request()` without panic
- [ ] New capabilities advertised to clients
- [ ] New handler overrides on `State` log incoming requests via `tracing::debug!`
- [ ] Version-gated scaffolding for new info state values in place
- [ ] Compositor starts in nested winit and existing behavior is unchanged
- [ ] `cargo clippy --all-features -- -D warnings` clean, no new warnings

## Post-Completion

- Archive this plan to `.cursor/plans-archive/phase-1-protocol-extension.md` per the Archive Rule in `.cursor/rules/core-enforcement.mdc`.
- Update `DEVELOPMENT.md` (append-only) to note the archival and Phase 1 completion status.
