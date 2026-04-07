Deep Research & Orientation: cosmic-comp-fork
1. Smithay — Architecture Overview
Smithay (v0.7.0, pinned to upstream git e84a4ca) is a Rust framework for building Wayland compositors. It is not a compositor itself — it provides building blocks:

Backend module — Hardware abstraction: DRM/KMS for displays, GBM/EGL for GPU buffers, libinput for input devices, libseat for session management. Also supports winit (for nested Wayland/X11 testing) and X11 backends.
Wayland module — Server-side protocol implementations: wl_compositor, xdg_shell, wl_seat, wl_shm, dmabuf, layer shell, data device (clipboard/DnD), presentation time, etc. Compositors implement handler traits and use delegate_*! macros to wire dispatch.
Desktop helpers — Window (wraps XDG toplevel or X11 surface), Space<E> (a 2D spatial container for elements with hit-testing and rendering), PopupManager, SpaceElement trait, layer maps per output.
Event loop — Built on calloop. State is passed as &mut self to handler callbacks — no Rc/Arc needed for the main state.
How Smithay handles windows: A smithay::desktop::Window is the canonical toplevel surface. Compositors wrap it in their own types. The Space<E> type tracks element positions and handles rendering order, pointer hit-testing, and damage tracking. Smithay does not provide window management policy (tiling, stacking order, etc.) — that's the compositor's job.

How cosmic-comp uses Smithay: CosmicSurface is a newtype around smithay::desktop::Window. The floating layer uses Space<CosmicMapped> for position tracking. Tiling uses a custom id_tree::Tree<Data> — Smithay's Space is not involved for tiled windows. All standard Wayland protocols are delegated through Smithay's handler trait implementations.

2. cosmic-comp Source Code Structure
The codebase is a single Rust crate (cosmic-comp) with a cosmic-comp-config sub-crate. Key architecture:

Entry point chain: main.rs → lib.rs::run() → State::new() → backend::init_backend_auto() → event loop

Central state (src/state.rs):

State — top level: backend: BackendData, common: Common
Common — holds shell: Arc<RwLock<Shell>>, all Wayland protocol state (toplevel_info_state, toplevel_management_state, workspace_state), display handle, clock, config, popup manager
Shell (src/shell/mod.rs) — the mutable center of window management:

Workspaces — IndexMap<Output, WorkspaceSet> + layout mode
WorkspaceSet — per-output: active index, workspaces: Vec<Workspace>, sticky_layer: FloatingLayout
Workspace (src/shell/workspace.rs) — owns one TilingLayout + one FloatingLayout + fullscreen + focus stacks
Element hierarchy (src/shell/element/):

CosmicSurface — wraps smithay::desktop::Window
CosmicWindow — single window with Iced-rendered decorations
CosmicStack — tabbed group of CosmicSurfaces with tab-strip UI
CosmicMapped — the unified mapped-element type (either CosmicWindow or CosmicStack), carrying associated state:

mod.rs
Lines 90-109
pub struct CosmicMapped {
    element: CosmicMappedInternal,
    pub maximized_state: Arc<Mutex<Option<MaximizedState>>>,
    //tiling
    pub tiling_node_id: Arc<Mutex<Option<NodeId>>>,
    //floating
    pub(super) resize_state: Arc<Mutex<Option<ResizeState>>>,
    pub last_geometry: Arc<Mutex<Option<Rectangle<i32, Local>>>>,
    pub moved_since_mapped: Arc<AtomicBool>,
    pub floating_tiled: Arc<Mutex<Option<TiledCorners>>>,
    //sticky
    pub previous_layer: Arc<Mutex<Option<ManagedLayer>>>,
    // ...
}
Tiling layout (src/shell/layout/tiling/mod.rs):

Binary tree via id_tree::Tree<Data> where internal nodes are Data::Group (orientation + proportional sizes) and leaves are Data::Mapped (a CosmicMapped + geometry)
TreeQueue for animated transitions with TilingBlocker (waits for configure acks)
Resize between tiles via ResizeForkTarget grabs
Floating layout (src/shell/layout/floating/mod.rs):

FloatingLayout wraps Space<CosmicMapped> for spatial tracking
spawn_order: Vec<CosmicMapped> tracks creation order
Supports TiledCorners (snap-to-corner pseudo-tiling for floating windows)
Animations for minimize/unminimize/tiled transitions
Protocol implementations (src/wayland/):

protocols/ — state machines for zcosmic protocols
handlers/ — trait implementations connecting protocol requests to Shell actions
3. Current zcosmic Protocols — Capabilities and Limitations
zcosmic_toplevel_info_v1 (version 3):

What it exposes: title, app_id, states (maximized, fullscreen, activated, minimized, sticky), output enter/leave, geometry per output, workspace enter/leave
What it does NOT expose: No z-order/stacking position. No way for a client to know "window A is above window B." No tiled-vs-floating distinction. No information about which tiling node a window occupies.
zcosmic_toplevel_manager_v1 (version 4):

Client can do: activate, close, set/unset fullscreen, set/unset maximized, set/unset minimized, set/unset sticky, move_to_ext_workspace, set_rectangle (for minimize animation targets)
Client CANNOT do: Move or resize a window to specific coordinates/size. Set tiled vs floating state. Control stacking/z-order. Atomically apply a complete layout (multiple moves, resizes, reorders in one transaction). The move_to_workspace request with zcosmic handles is actually a no-op in current code — only move_to_ext_workspace works.
Advertised capabilities: Close, Activate, Maximize, Minimize, MoveToWorkspace
zcosmic_workspace_manager_v2 (version 2):

Client can do: rename, set_tiling_state, pin/unpin, move_before/move_after (reorder), activate workspace
Client CANNOT do: Create workspaces programmatically. Query the full tiling tree structure.
Key gaps for our goals: There is no protocol mechanism for a client to:

Set exact position and size of a window
Toggle a window between tiled and floating
Control stacking/z-order of floating windows
Read or write the tiling tree structure
Perform atomic "batch" layout operations
4. Issue #3402 and Related Issues
Issue #3402 — "Externalize window management via API" (pop-os/cosmic-epoch, opened 2026-03-29):

Proposes a plugin/API system so users can bring their own tiling layout
Suggests Wasm+WIT or Lua as extension mechanisms
The upstream maintainer (@Drakulix) responded that the more realistic approach is running COSMIC shell with a different compositor entirely (see cosmic-ext-extra-sessions), not embedding a plugin API
This means upstream is unlikely to add a generalized window management API soon
Related stacking/layout issues:

#3377 — Floating windows always render above tiled, regardless of focus (acknowledged as intentional i3/sway-like behavior, significant refactoring needed to change)
#2526 — Discussion about floating and tiling window ordering, same theme
#1838 — Maximizing/restoring snapped windows restores to wrong position (intermediate drag position stored instead of final)
#388 — Non-resizable windows in stacks affect other stack members
#1339 — Stack navigation loops unexpectedly
These issues confirm that stacking order, position restore, and tiled/floating state management are real pain points with no upstream solution on the horizon.

5. Best Practices for Developing & Testing a Wayland Compositor
The fundamental risk: A Wayland compositor IS your display server. A crash or bad state = black screen / frozen session. You must isolate testing from your working environment.

Three-layer approach:

Build on your main user account — Code editing, compilation, git operations. This is just normal Rust development. cargo build in your main session is perfectly safe.

Quick iteration: Nested Wayland via winit backend — cosmic-comp has a built-in winit backend (src/backend/winit.rs) that runs the compositor inside a window on your existing session. Launch with environment variable or flag to select winit. Good for:

Verifying the compositor starts without crashing
Testing protocol additions (your client can connect to the nested compositor's socket)
Checking basic layout behavior
Limitations: No multi-monitor, no DRM, slightly different rendering path, some features may behave differently
Full testing: Separate TTY / user account — For real testing of your modified compositor as the actual session compositor:

Create a separate user (e.g., testuser) with its own home directory
Switch to a different TTY (Ctrl+Alt+F3)
Log in as testuser, launch your custom cosmic-comp binary
Your main session on TTY1/2 remains untouched and recoverable
If the test compositor crashes, switch back to your main TTY
This tests the real KMS/DRM backend, multi-monitor, and actual session behavior
6. Our Specific Goals with This Fork
Based on the gaps identified above, our cosmic-comp-fork aims to add compositor-side capabilities that our cosmic-layout-presets client application needs to reliably save and restore exact window layouts:

Precise stacking order — A client must be able to read the z-order of floating windows and set a specific z-order. Currently, zcosmic_toplevel_info exposes no stacking position, and there's no request to raise/lower a window to a specific position in the stack.

Reliable floating vs tiled state — A client must be able to:

Query whether a window is currently tiled or floating
Toggle a window between tiled and floating
Currently, this distinction is internal to CosmicMapped (whether it lives in TilingLayout vs FloatingLayout) and is not exposed via any protocol.
Exact position/size restore — A client must be able to set a floating window to exact pixel coordinates and dimensions. The current zcosmic_toplevel_manager has no set_position or set_size request. The compositor must add these.

Atomic "apply exact layout" — For restoring a complete saved layout, the client needs to batch multiple operations (move windows to workspaces, set tiled/floating, set positions/sizes, set stacking order) and have them applied atomically (or at least in a coordinated, consistent manner), avoiding visual glitches from partial application.

7. How Goals Map to Compositor Changes
Goal	Compositor area to extend	Specific changes needed
Stacking order	zcosmic_toplevel_info + FloatingLayout	Add z-index/stacking-position to toplevel info events. Add raise_to/set_stacking_order request to management protocol. Implement in FloatingLayout::space (Smithay Space has raise_element).
Tiled vs floating state	zcosmic_toplevel_info + Shell/Workspace	Add tiled/floating state flag to info events. Add set_tiled/set_floating request to management. Wire through Workspace::toggle_floating/toggle_tiling.
Exact position/size	zcosmic_toplevel_manager + FloatingLayout	Add set_position(x, y) and set_size(w, h) requests. Implement by calling Space::map_element with new position and sending configure with new size.
Atomic batch apply	New protocol or management extension	Add a transaction/batch mechanism: client opens a "layout transaction," queues multiple operations, then commits them all at once. Compositor applies during a single frame.
Key files we'll modify:

src/wayland/protocols/toplevel_info.rs — extend Window trait, add new events
src/wayland/protocols/toplevel_management.rs — add new request types and capabilities
src/wayland/handlers/toplevel_management.rs — implement new request handlers
src/shell/layout/floating/mod.rs — implement position/size/stacking mutations
src/shell/workspace.rs — implement tiled↔floating transitions via protocol
src/shell/mod.rs — coordinate batch operations across workspaces
We'll also need to extend or fork cosmic-protocols to define the new XML protocol extensions (new requests/events), or define a custom protocol XML in this repo.

8. Recommended Development Workflow
Setup:

Main account (tes)     →  Code, build, git
  └── Nested winit     →  Quick smoke tests (run cosmic-comp inside a window)
Test account (testcomp) →  Full session tests on separate TTY
Step-by-step:

Code & build on your main account:

cd /home/tes/cosmic-comp-fork
cargo build          # debug build for iteration
cargo build --release  # for session testing
Quick check via nested winit (from your main Wayland session):

COSMIC_BACKEND=winit ./target/debug/cosmic-comp
Then point test clients at the nested compositor's WAYLAND_DISPLAY socket.

Full session test on a separate TTY:

Create a testcomp user (once): sudo useradd -m testcomp
Copy your built binary: sudo cp target/release/cosmic-comp /usr/local/bin/cosmic-comp-fork
Switch TTY: Ctrl+Alt+F3, log in as testcomp
Launch: COSMIC_COMP=/usr/local/bin/cosmic-comp-fork cosmic-session (or start the binary directly with appropriate environment)
If it crashes: Ctrl+Alt+F1 back to your main session, fix, rebuild, retry
Never replace the system compositor on your main account until changes are well-tested.

Version control discipline: Commit working states frequently. Use feature branches. Keep master buildable and matching upstream so you can always recover.

Summary
We have a clear, complete picture:

Smithay provides the Wayland plumbing; cosmic-comp adds the window management policy (tiling tree, floating space, stacking, workspaces)
The existing zcosmic protocols are read-heavy and action-limited — they can list windows and do basic operations (activate, maximize, minimize, move to workspace) but cannot set positions, toggle tiled/floating, control stacking order, or batch operations
Upstream is not planning to add an externalized window management API (they suggest using a different compositor entirely)
Our fork will extend the zcosmic protocols with precisely the capabilities our cosmic-layout-presets client needs: exact position/size, tiled/floating toggle, stacking order control, and atomic batch application
Development is safe using the nested winit backend for quick checks and a separate test user account for full session testing
We're ready to proceed with creating the project structure when you give the word.