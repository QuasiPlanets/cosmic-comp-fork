# Architecture Overview

This document covers the parts of cosmic-comp relevant to our protocol extension goals. It is not a full compositor reference -- it focuses on the layout engine, window management, zcosmic protocols, and the specific areas we plan to extend.

## Smithay Integration

cosmic-comp is built on [Smithay](https://github.com/Smithay/smithay) v0.7.0 (pinned to upstream git commit `e84a4ca`). Smithay provides:

- **Backend abstraction**: DRM/KMS, GBM/EGL, libinput, libseat, winit (for nested testing)
- **Wayland protocol server**: `wl_compositor`, `xdg_shell`, `wl_seat`, `wl_shm`, `dmabuf`, layer shell, etc.
- **Desktop helpers**: `Window`, `Space<E>`, `PopupManager`, `SpaceElement` trait
- **Event loop**: Built on `calloop` with `&mut self` state passing

cosmic-comp wraps Smithay types in its own hierarchy and adds all window management policy (tiling, floating, stacking, workspaces) on top.

## Core Type Hierarchy

```
State (src/state.rs)
└── Common
    ├── shell: Arc<RwLock<Shell>>     -- the mutable center of window management
    ├── toplevel_info_state           -- zcosmic_toplevel_info protocol state
    ├── toplevel_management_state     -- zcosmic_toplevel_manager protocol state
    ├── workspace_state               -- workspace protocol state
    └── (many other Wayland globals)

Shell (src/shell/mod.rs)
└── Workspaces: IndexMap<Output, WorkspaceSet>
    └── WorkspaceSet (per output)
        ├── active: usize
        ├── workspaces: Vec<Workspace>
        └── sticky_layer: FloatingLayout

Workspace (src/shell/workspace.rs)
├── tiling_layer: TilingLayout
├── floating_layer: FloatingLayout
├── fullscreen: Option<...>
├── focus_stack: FocusStacks
└── handle: WorkspaceHandle

CosmicMapped (src/shell/element/mod.rs)
├── element: CosmicWindow | CosmicStack
├── maximized_state
├── tiling_node_id          -- links to TilingLayout tree node
├── last_geometry            -- previous geometry (for restore)
├── floating_tiled           -- snap-to-corner state
└── previous_layer           -- for sticky windows
```

## Layout Engine

### Tiling (src/shell/layout/tiling/mod.rs)

The tiling layout uses a binary tree (`id_tree::Tree<Data>`) where:
- **Internal nodes** are `Data::Group` with `Orientation` (horizontal/vertical) and proportional `sizes: Vec<i32>`
- **Leaf nodes** are `Data::Mapped` holding a `CosmicMapped` and its geometry
- **Placeholder nodes** are `Data::Placeholder` for drag/drop targets

`TilingLayout` maintains a `TreeQueue` for animated transitions, with `TilingBlocker` to wait for client configure acks before finalizing layouts.

Key operations: `add_window`, `remove_window`, `swap_windows`, `update_geometry` (recomputes all positions from the tree structure).

### Floating (src/shell/layout/floating/mod.rs)

The floating layout wraps Smithay's `Space<CosmicMapped>` for spatial tracking:
- `space: Space<CosmicMapped>` -- positions, hit-testing, rendering order
- `spawn_order: Vec<CosmicMapped>` -- creation order tracking
- `animations: HashMap<CosmicMapped, Animation>` -- minimize/unminimize/tiled transitions

Position and size are managed through `Space::map_element` (set position) and Wayland configure events (set size). Stacking order within the Space is managed by `Space::raise_element`.

### Stacking / Tab Groups (src/shell/element/stack.rs)

`CosmicStack` groups multiple `CosmicSurface`s into a single tabbed element with an Iced-rendered tab strip. A stack participates in tiling or floating as a single `CosmicMapped` leaf.

## Window Type Chain

```
CosmicSurface (src/shell/element/surface.rs)
  = newtype around smithay::desktop::Window
  Implements the Window trait for ToplevelInfoState

CosmicWindow (src/shell/element/window.rs)
  = single window with Iced-rendered decorations

CosmicStack (src/shell/element/stack.rs)
  = tabbed group of CosmicSurfaces

CosmicMapped (src/shell/element/mod.rs)
  = CosmicWindow | CosmicStack (via space_elements! macro)
  The unified type used by TilingLayout and FloatingLayout
```

## Current zcosmic Protocols

### zcosmic_toplevel_info_v1 (version 3)

**Exposes to clients:** title, app_id, states (maximized, fullscreen, activated, minimized, sticky), output enter/leave, geometry per output, workspace membership.

**Does NOT expose:**
- Stacking order / z-index
- Whether the window is tiled or floating
- Position within the tiling tree
- Tab group membership

**Key files:**
- State: `src/wayland/protocols/toplevel_info.rs`
- Handler: `src/wayland/handlers/toplevel_info.rs`

### zcosmic_toplevel_manager_v1 (version 4)

**Client can request:** activate, close, fullscreen/unfullscreen, maximize/unmaximize, minimize/unminimize, sticky/unsticky, move_to_ext_workspace, set_rectangle.

**Client CANNOT request:**
- Set exact position (x, y)
- Set exact size (width, height)
- Toggle tiled vs floating
- Set stacking order / z-index
- Batch/atomic operations

**Advertised capabilities:** Close, Activate, Maximize, Minimize, MoveToWorkspace.

**Key files:**
- State: `src/wayland/protocols/toplevel_management.rs`
- Handler: `src/wayland/handlers/toplevel_management.rs`

### zcosmic_workspace_manager_v2 (version 2)

**Client can request:** rename, set_tiling_state, pin/unpin, move_before/move_after (reorder), activate.

**Key files:**
- State: `src/wayland/protocols/workspace/` (mod.rs, cosmic_v2.rs, ext.rs)
- Handler: `src/wayland/handlers/workspace.rs`

## Protocol Gap Analysis

| Capability needed | Current protocol support | Gap |
|---|---|---|
| Read stacking order | None | No z-index in toplevel_info events |
| Set stacking order | None | No raise/lower/set_z_index request |
| Read tiled vs floating | None | No state flag in toplevel_info |
| Toggle tiled/floating | None | No request in toplevel_manager |
| Set exact position | None | No set_position request |
| Set exact size | None | No set_size request |
| Atomic batch apply | None | No transaction mechanism |

## Extension Targets

### Files we will modify

| File | Change |
|---|---|
| `src/wayland/protocols/toplevel_info.rs` | Add tiled/floating state, stacking position to events |
| `src/wayland/protocols/toplevel_management.rs` | Add new request types and capabilities |
| `src/wayland/handlers/toplevel_management.rs` | Implement set_position, set_size, toggle_floating, set_stacking_order |
| `src/shell/layout/floating/mod.rs` | Expose position/size/stacking mutations via Shell |
| `src/shell/workspace.rs` | Implement tiled-to-floating transitions triggered by protocol |
| `src/shell/mod.rs` | Coordinate batch operations across workspaces |

### Protocol XML

New protocol requests and events will be defined as extensions to the existing zcosmic protocols. This requires either forking `cosmic-protocols` or defining a new protocol XML in this repository. The approach will be determined in Phase 1.

## Key File Index

| Area | Path |
|---|---|
| Entry point | `src/main.rs`, `src/lib.rs` |
| Central state | `src/state.rs` (State, Common) |
| Shell core | `src/shell/mod.rs` (Shell, Workspaces, WorkspaceSet) |
| Workspace | `src/shell/workspace.rs` |
| Tiling layout | `src/shell/layout/tiling/mod.rs` |
| Floating layout | `src/shell/layout/floating/mod.rs` |
| Layout glue | `src/shell/layout/mod.rs` (tiling exceptions) |
| Element types | `src/shell/element/mod.rs` (CosmicMapped) |
| Surface wrapper | `src/shell/element/surface.rs` (CosmicSurface) |
| Window element | `src/shell/element/window.rs` (CosmicWindow) |
| Stack element | `src/shell/element/stack.rs` (CosmicStack) |
| Toplevel info protocol | `src/wayland/protocols/toplevel_info.rs` |
| Toplevel mgmt protocol | `src/wayland/protocols/toplevel_management.rs` |
| Toplevel mgmt handler | `src/wayland/handlers/toplevel_management.rs` |
| Workspace protocol | `src/wayland/protocols/workspace/` |
| Focus system | `src/shell/focus/` |
| Input handling | `src/input/` |
| Backend (winit) | `src/backend/winit.rs` |
| Backend (KMS) | `src/backend/kms/` |

## Client Requirements — cosmic-layout-presets

The [cosmic-layout-presets](https://github.com/QuasiPlanets/cosmic-layout-presets) client application saves and restores named window layout presets. It uses `zcosmic_toplevel_info_v1`, `zcosmic_toplevel_manager_v1`, and `ext_workspace_v1` via `cosmic-client-toolkit` (cctk).

### What the client can already do

- List all toplevels with app_id, title, state flags, geometry, and workspace membership
- Toggle maximize, minimize, fullscreen states
- Move windows between workspaces
- Activate (focus) windows in a specific order
- Launch missing apps via XDG desktop files (best-effort)
- Minimize windows not in the preset

### What the client captures but cannot restore

The client records `x`, `y`, `width`, `height`, tiled/floating state, and `stack_order` during capture. On apply, these fields are either discarded or approximated because the protocol has no matching requests or events.

### Gap Table

| Capability needed | Client workaround | Why current protocol is insufficient | Proposed new protocol feature |
|---|---|---|---|
| Restore exact position | Position captured but ignored on apply | No `set_position` request exists for foreign toplevels | `set_position(handle, x, y)` on `zcosmic_toplevel_manager` |
| Restore exact size | Size captured but ignored on apply | No `set_size` request exists for foreign toplevels | `set_size(handle, w, h)` on `zcosmic_toplevel_manager` |
| Set window to floating | No reliable workaround; client tries `UnsetMaximized` + `UnsetMinimized` but compositor often keeps window tiled | No `set_floating` request; no way to move a window from tiling to floating layer | `set_floating(handle)` on `zcosmic_toplevel_manager` |
| Set window to tiled | Not attempted; no protocol path exists | No `set_tiled` request; no way to move a window from floating to tiling layer | `set_tiled(handle)` on `zcosmic_toplevel_manager` |
| Read actual tiled/floating state | Inferred from absence of other state flags (unreliable; no dedicated flag exists) | `zcosmic_toplevel_info` has no tiled/floating flag | `floating_state` event on `zcosmic_toplevel_info` |
| Read actual z-order | True z-order is unavailable; client uses activation history as a weak proxy (`stack_order`) | `zcosmic_toplevel_info` has no stacking position | `stacking_order` event on `zcosmic_toplevel_info` |
| Set specific z-order | `Activate` replayed in captured order (partial effect; compositor may reorder differently) | No raise/lower/set-z-index request | `set_stacking_order(handle, z_index)` on `zcosmic_toplevel_manager` |
| Apply full layout atomically | Sequential requests with heuristic delays (~3s wait, 2-pass unset) | No transaction or batch mechanism | `begin_layout_transaction` / `commit_layout_transaction` |

### Client integration point

The client's `src/wayland_handler.rs` defines a `ToplevelAction` enum with the protocol operations it can currently send:

```
Activate, Close, SetMaximized, UnsetMaximized, SetMinimized,
UnsetMinimized, UnsetFullscreen, MoveToWorkspace
```

New compositor capabilities will be consumed by adding variants to this enum (e.g., `SetPosition(handle, x, y)`, `SetSize(handle, w, h)`, `SetFloating(handle)`, `SetTiled(handle)`, `SetStackingOrder(handle, z_index)`) and dispatching them in `handle_toplevel_action` to the corresponding `zcosmic_toplevel_manager` requests.

The `ToplevelInfoHandler` implementation will receive the new events (`floating_state`, `stacking_order`) and relay them through `WaylandUpdate` to the main app model.
