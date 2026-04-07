# Phase 2 Sub-Agent: Shell Implementation

## Pre-Work: Re-Read All Project Documents

Before any code changes, re-read in full:

- [ARCHITECTURE.md](../../ARCHITECTURE.md) (especially the "Client Requirements -- cosmic-layout-presets" section and the "Extension Targets" table)
- [DEVELOPMENT.md](../../DEVELOPMENT.md) (especially the Phase 1 Summary for exact details of what was implemented)
- [SAFETY.md](../../SAFETY.md)
- [.cursor/rules/core-enforcement.mdc](../rules/core-enforcement.mdc)

If any clarification is needed about Phase 1 decisions or implementation details, ask the existing Phase1-Protocol-Extension sub-agent (agent ID `22fb0a47-5ddc-41ba-b032-1de309d79441`).

After reading the updated DEVELOPMENT.md (which includes the Phase 1 Summary), proceed with implementation.

## Objective

Wire the Phase 1 protocol scaffolding to actual Shell operations. Replace all 5 no-op `tracing::debug!` handlers with real Shell calls, and enable sending `tiled`/`floating` state values and `stacking_order` events to clients.

## Dependency Rule

No third-party crates will be added. All changes use only official cosmic-comp, Smithay, and cosmic-protocols code.

## Scope and Boundaries

### In scope (Phase 2)

- Add 5 new Shell helper methods in `src/shell/mod.rs`
- Replace 5 no-op handlers in `src/wayland/handlers/toplevel_management.rs` with real Shell calls
- Enable tiled/floating state and stacking_order event sending in `src/wayland/protocols/toplevel_info.rs`
- Possibly expose helpers in `src/shell/workspace.rs` and `src/shell/layout/floating/mod.rs`

### Out of scope (deferred)

- Protocol XML changes (Phase 1, complete)
- `begin_layout_transaction` / `commit_layout_transaction` (Phase 4)
- Client-side integration testing (Phase 3)
- Documentation updates to DEVELOPMENT.md (main agent responsibility)

## Implementation Todos (ordered, one at a time)

### 1. Add 5 new Shell helper methods (`p2-shell-methods`)

In `src/shell/mod.rs`, add public methods following the pattern of `maximize_request`, `minimize_request`, etc.:

- `set_window_position(surface, x, y)` -- floating only, output-relative coordinates
- `set_window_size(surface, width, height)` -- clamp to min/max, send configure
- `set_window_floating(surface, seat)` -- move tiled window to floating layer
- `set_window_tiled(surface, seat)` -- move floating window to tiling layer
- `set_window_stacking_order(surface, order)` -- raise/reorder in floating space

### 2. Wire management handlers (`p2-wire-handlers`)

In `src/wayland/handlers/toplevel_management.rs`, replace the 5 `tracing::debug!` no-ops with real Shell calls following the existing handler pattern (`self.common.shell.write()` -> call Shell method).

### 3. Enable info state sending (`p2-info-state`)

In `src/wayland/protocols/toplevel_info.rs`, enable the version-gated scaffolding to actually send `tiled`/`floating` state flags and `stacking_order` events. Use the LayoutMeta refresh-time query approach (Option B from Phase 1).

### 4. Verify (`p2-verify`)

- `cargo check` passes
- `cargo clippy --all-features -- -D warnings` clean
- Show clear diffs for every changed file

## Safety Rules

- No `unwrap()` or `panic!()` in new code -- use `if let` / `tracing::warn!`
- Clamp positions/sizes to output work area; reject negative dimensions
- `set_floating` and `set_tiled` must check `workspace.tiling_enabled`
- Existing behavior must be completely unchanged for all existing protocol requests

## Success Criteria

- `set_position` moves a floating window to exact (x, y) coordinates
- `set_size` resizes a window to exact (w, h) dimensions (client receives configure)
- `set_floating` moves a tiled window to the floating layer
- `set_tiled` moves a floating window to the tiling layer
- `set_stacking_order` changes the z-order of floating windows
- Clients receive `tiled`/`floating` state flags in toplevel info events
- Clients receive `stacking_order` events with correct z-indices
- Existing behavior unchanged
- `cargo clippy --all-features -- -D warnings` clean, zero warnings
