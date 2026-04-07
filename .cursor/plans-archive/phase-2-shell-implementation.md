---
name: Phase 2 Shell Implementation
overview: Wire the Phase 1 protocol scaffolding to actual Shell operations — replace 5 no-op handlers with real implementations, and enable sending tiled/floating state and stacking_order events to clients.
todos:
  - id: p2-shell-methods
    content: Add 5 new Shell helper methods in src/shell/mod.rs (set_window_position/size/floating/tiled/stacking_order)
    status: pending
  - id: p2-wire-handlers
    content: Replace 5 no-op handlers in src/wayland/handlers/toplevel_management.rs with real Shell calls
    status: pending
  - id: p2-info-state
    content: Enable tiled/floating state and stacking_order event sending in toplevel_info.rs (LayoutMeta approach)
    status: pending
  - id: p2-verify
    content: cargo check + clippy + Tier 2 nested winit smoke test
    status: pending
isProject: false
---

# Phase 2: Compositor-Side Shell Implementation

## Pre-Work: Re-Read All Project Documents

Before any code changes, the implementer must re-read in full:

- [ARCHITECTURE.md](ARCHITECTURE.md) (especially the "Client Requirements -- cosmic-layout-presets" section and the "Extension Targets" table)
- [DEVELOPMENT.md](DEVELOPMENT.md) (especially the Phase 1 Summary for exact details of what was implemented)
- [SAFETY.md](SAFETY.md)
- [.cursor/rules/core-enforcement.mdc](.cursor/rules/core-enforcement.mdc)

If any clarification is needed about Phase 1 decisions or implementation details, ask the existing Phase1-Protocol-Extension sub-agent (defined in `.cursor/agents/Phase1-Protocol-Extension.md`, agent ID `22fb0a47-5ddc-41ba-b032-1de309d79441`).

After the main agent updates DEVELOPMENT.md with the Phase 1 summary, re-read the updated DEVELOPMENT.md before starting implementation.

## Dependency Rule

No third-party crates will be added. All changes use only official cosmic-comp, Smithay, and cosmic-protocols code.

## Goal

Replace the 5 Phase 1 no-op `tracing::debug!` handlers with real Shell calls, and enable sending the new `tiled`/`floating` state values and `stacking_order` event to clients.

Phase 1 established the protocol surface (XML, traits, dispatch, capabilities). Phase 2 makes it functional. Phase 3 tests end-to-end with the client. Phase 4 adds transactions.

## Existing Shell APIs (what we build on)

These methods already exist and provide the core functionality Phase 2 needs:

- **Position**: `FloatingLayout::map(mapped, Some(Point))` and `FloatingLayout::map_internal(mapped, position, size, prev)` — set exact coordinates via `Space::map_element` (`[src/shell/layout/floating/mod.rs:399-612](src/shell/layout/floating/mod.rs)`)
- **Size**: `CosmicMapped::set_geometry(rect)` + `CosmicMapped::configure()` — sends xdg configure to client (`[src/shell/element/mod.rs:458-470](src/shell/element/mod.rs)`, `[src/shell/element/surface.rs:219-241](src/shell/element/surface.rs)`)
- **Tiled/floating toggle**: `Workspace::toggle_floating_window(seat, window)` — unmaps from one layer and maps to the other (`[src/shell/workspace.rs:1402-1430](src/shell/workspace.rs)`)
- **Raise**: `Space::raise_element(element, true)` — raises a floating window to top (`[src/shell/focus/mod.rs:421-449](src/shell/focus/mod.rs)`)
- **Query state**: `Workspace::is_floating(surface)` and `Workspace::is_tiled(surface)` (`[src/shell/workspace.rs:1452-1482](src/shell/workspace.rs)`)
- **Element lookup**: `Shell::element_for_surface(surface)` — finds `CosmicMapped` from `CosmicSurface` across all workspaces (`[src/shell/mod.rs:2032-2051](src/shell/mod.rs)`)

## Implementation Plan

### Part A: New Shell Helper Methods

Add new public methods to `Shell` in `[src/shell/mod.rs](src/shell/mod.rs)` that the protocol handlers will call. These follow the exact same pattern as existing Shell methods (`maximize_request`, `minimize_request`, etc.) — they resolve the workspace, validate preconditions, and delegate to `Workspace` or `FloatingLayout`.

`**Shell::set_window_position(&mut self, surface, x: i32, y: i32)`**

- Find workspace via `element_for_surface` + workspace lookup
- Verify window is floating (not tiled) — if tiled, `tracing::warn!` and return
- Convert (x, y) to `Point<i32, Local>` (output-relative)
- Call `floating_layer.space.map_element(mapped, Point::from((x, y)), false)` to reposition
- Call `mapped.set_geometry(...)` to update stored geometry
- No configure needed (position-only change for Wayland toplevels)

`**Shell::set_window_size(&mut self, surface, width: i32, height: i32)`**

- Find workspace + element
- Clamp to min/max surface size and output bounds
- Call `mapped.set_geometry(new_rect)` + `mapped.configure()` (sends xdg configure)
- Reposition in floating space if geometry changed

`**Shell::set_window_floating(&mut self, surface, seat)`**

- Find workspace + element
- If already floating, no-op
- If tiled and `tiling_enabled`: unmap from `tiling_layer`, map to `floating_layer` (mirrors the "tiled to floating" branch of `toggle_floating_window`)
- If tiling not enabled, no-op (everything is floating already)

`**Shell::set_window_tiled(&mut self, surface, seat)`**

- Find workspace + element
- If already tiled, no-op
- If floating and `tiling_enabled`: unmap from `floating_layer`, map to `tiling_layer` (mirrors the "floating to tiled" branch of `toggle_floating_window`)
- If tiling not enabled, `tracing::warn!` and return (can't tile on non-tiling workspace)

`**Shell::set_window_stacking_order(&mut self, surface, order: u32)`**

- Find workspace + element
- Verify floating
- Phase 2 approach: use `space.raise_element(mapped, true)` as a "raise to top" semantic. Full arbitrary z-index ordering is complex (requires reordering all elements) and may be deferred to Phase 3/4 if needed. For now, treat `order` as a relative priority and raise in ascending order from the client's perspective.
- Alternative: iterate `space.elements()`, collect, re-map in desired order. This is more complete but riskier.

### Part B: Wire Management Handlers

Replace the 5 no-ops in `[src/wayland/handlers/toplevel_management.rs](src/wayland/handlers/toplevel_management.rs)` (lines 263-306) with real Shell calls, following the exact pattern of existing handlers:

```rust
fn set_position(&mut self, _dh: &DisplayHandle, window: &..., x: i32, y: i32) {
    let mut shell = self.common.shell.write();
    shell.set_window_position(window, x, y);
}
```

Each handler: `self.common.shell.write()` -> call Shell method -> drop shell if `set_focus` needed afterward.

### Part C: Enable Info State Sending

This is the most architecturally interesting part. The `send_toplevel_to_client` function in `[src/wayland/protocols/toplevel_info.rs](src/wayland/protocols/toplevel_info.rs)` needs to emit `tiled`/`floating` state flags and `stacking_order` events. But it only receives a `Window` (which is `CosmicSurface`) and has no direct access to `Shell`.

**Proposed approach (Option B from Phase 1 plan — refresh-time query):**

1. Add a new struct to `ToplevelInfoState` or `ToplevelStateInner` that stores per-window layout metadata:

```rust
struct LayoutMeta {
    is_floating: bool,
    is_tiled: bool,
    stacking_order: Option<u32>,  // None if not floating
}
```

1. Before `ToplevelInfoState::refresh()` is called from the compositor main loop, compute `LayoutMeta` for each tracked toplevel by querying `Shell::is_floating` / `Shell::is_tiled` and reading floating space element order. Store these in a `HashMap` on `ToplevelInfoState` keyed by the window.
2. In `send_toplevel_to_client`, look up the pre-computed `LayoutMeta` and emit the state flags and event.

**Key files**: Find where `toplevel_info_state.refresh()` is called — likely in the main compositor loop. Add the pre-computation step there.

**Stacking order computation**: Iterate `floating_layer.space.elements()` (bottom to top), assign index 0, 1, 2, ... to each element. Map `CosmicMapped` back to `CosmicSurface` to match toplevels.

### Part D: Verify

1. `cargo check` passes after each sub-step
2. `cargo clippy --all-features -- -D warnings` clean
3. Tier 2: `COSMIC_BACKEND=winit ./target/debug/cosmic-comp` starts, existing behavior unchanged
4. Tier 2: Verify new requests work (open windows, send protocol requests via test client or `cosmic-layout-presets`)
5. Tier 2: Verify tiled/floating state and stacking_order events are received by clients

## Files to Modify


| File                                                                                         | Change                                                                                       |
| -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `[src/shell/mod.rs](src/shell/mod.rs)`                                                       | Add 5 new Shell methods (set_window_position/size/floating/tiled/stacking_order)             |
| `[src/shell/workspace.rs](src/shell/workspace.rs)`                                           | Possibly expose helpers if toggle_floating_window needs adaptation for non-seat-driven calls |
| `[src/shell/layout/floating/mod.rs](src/shell/layout/floating/mod.rs)`                       | Possibly add a `set_element_position` or `reorder_element` helper if needed                  |
| `[src/wayland/handlers/toplevel_management.rs](src/wayland/handlers/toplevel_management.rs)` | Replace 5 no-op handlers with Shell calls                                                    |
| `[src/wayland/protocols/toplevel_info.rs](src/wayland/protocols/toplevel_info.rs)`           | Enable tiled/floating state and stacking_order event sending; add LayoutMeta pre-computation |


Files **not** modified: `src/wayland/protocols/toplevel_management.rs` (trait already complete from Phase 1), `Cargo.toml`, protocol XML (no protocol changes in Phase 2), `DEVELOPMENT.md` (documentation updates are handled by the main agent, not the implementer).

## Safety and Testing

- **Tier 1 (Build):** `cargo check` + `cargo clippy` after each step. Required.
- **Tier 2 (Nested winit):** Required after each Part. Verify compositor starts, existing window ops work, new requests have visible effects.
- **Tier 3 (Separate test user):** Recommended after full Phase 2, especially for set_floating/set_tiled which move windows between layout layers and could affect focus/input.
- **No `unwrap()` or `panic!`** in new code. Use `if let` / `tracing::warn!` for precondition failures.
- **Bound checks:** Clamp positions/sizes to output work area. Reject negative dimensions.
- **Tiling guard:** `set_floating` and `set_tiled` must check `workspace.tiling_enabled` before attempting layer transitions.

## Open Questions / Design Decisions

1. **set_stacking_order semantics**: Should `order` be treated as absolute z-index (requiring full reorder of all floating elements) or relative (just raise to top)? Absolute is more useful for layout restore but more complex. Recommend: implement full reorder if Smithay's Space API supports it; fall back to sequential raise in order.
2. **set_position/set_size for tiled windows**: Should these be silently ignored (with warn log) or should they auto-toggle to floating first? Recommend: silently ignore with `tracing::warn!` — the client should explicitly call `set_floating` first if it wants to position a tiled window.
3. **Seat requirement for toggle_floating_window**: The existing `toggle_floating_window` takes a `&Seat`. Protocol handlers get the seat from `shell.seats.last_active()`. Verify this is correct for multi-seat scenarios (likely fine for COSMIC since it's single-seat).
4. **LayoutMeta refresh timing**: Should we compute layout metadata every frame or only when the topology changes? Every frame is simpler but slightly wasteful. Recommend: every frame for Phase 2 simplicity; optimize in Phase 3 if profiling shows it matters.

Final design decisions (such as stacking_order semantics and LayoutMeta refresh timing) will be made during implementation, with input from the existing Phase1-Protocol-Extension sub-agent if clarification is needed.

## Success Criteria

- `set_position` moves a floating window to exact (x, y) coordinates
- `set_size` resizes a window to exact (w, h) dimensions (client receives configure)
- `set_floating` moves a tiled window to the floating layer
- `set_tiled` moves a floating window to the tiling layer
- `set_stacking_order` changes the z-order of floating windows
- Clients receive `tiled`/`floating` state flags in toplevel info events
- Clients receive `stacking_order` events with correct z-indices
- Existing behavior (keyboard shortcuts, mouse operations, other protocol requests) is completely unchanged
- `cargo clippy --all-features -- -D warnings` clean
- Compositor starts in nested winit without issues

## Archive Rule

After this plan is approved and implemented, the **main agent** (not the implementer sub-agent) will:

1. Copy this plan to `.cursor/plans-archive/phase-2-shell-implementation.md` per the Archive Rule in `[.cursor/rules/core-enforcement.mdc](.cursor/rules/core-enforcement.mdc)`.
2. Update `DEVELOPMENT.md` (append-only) to note the archival and Phase 2 completion status.

