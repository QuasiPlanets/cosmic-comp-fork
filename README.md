# cosmic-comp-fork

A focused fork of [pop-os/cosmic-comp](https://github.com/pop-os/cosmic-comp) that extends the COSMIC compositor's Wayland protocols to support programmatic, precise window layout management.

This fork is the compositor-side companion to [cosmic-layout-presets](https://github.com/QuasiPlanets/cosmic-layout-presets), a client application that saves and restores exact window layouts.

## Goals

The upstream `zcosmic_toplevel_info` and `zcosmic_toplevel_manager` protocols provide basic window operations (activate, maximize, minimize, move to workspace) but lack the precision needed for full layout save/restore. This fork extends them with four capabilities:

1. **Precise stacking order** -- Read and set the z-order of floating windows. Currently no protocol exposes stacking position or allows raising/lowering a window to a specific z-index.

2. **Reliable floating vs tiled state** -- Query whether a window is tiled or floating, and toggle between the two. This distinction is currently internal to the compositor (`TilingLayout` vs `FloatingLayout`) and not exposed to clients.

3. **Exact position/size restore** -- Set a floating window to exact pixel coordinates and dimensions. The current protocol has no `set_position` or `set_size` request.

4. **Atomic "apply exact layout"** -- Batch multiple layout operations (move to workspace, set tiled/floating, set position/size, set stacking order) and apply them in a single coordinated transaction, avoiding visual glitches from partial application.

## Safety Warning

**A Wayland compositor IS your display server.** A crash or invalid state in the compositor means a black screen with no mouse or keyboard input. You cannot recover from within the same session.

Read [SAFETY.md](SAFETY.md) before making any changes. The short version:

- **Never** replace your daily-driver compositor with an untested build.
- **Never** run a debug build as your session compositor (panics are fatal).
- **Always** test on a separate user account before considering broader use.

## Development Workflow

This project uses a three-tier isolation strategy to keep your main desktop session safe while developing compositor changes.

### Tier 1: Build Only (main account)

Your main user account (`tes`) is for coding, building, and git operations only. Building the compositor is completely safe -- it does not affect your running session.

```bash
cd ~/cosmic-comp-fork
cargo check          # fast type checking
cargo build          # debug build for iteration
cargo build --release  # optimized build for session testing
```

### Tier 2: Nested Winit (quick smoke tests)

Run the compositor inside a window on your existing Wayland session using the winit backend. Crashes only kill the nested window, not your session.

```bash
COSMIC_BACKEND=winit ./target/debug/cosmic-comp
```

Connect test clients to the nested compositor's `WAYLAND_DISPLAY` socket. Limitations: no multi-monitor, no DRM, some features behave differently than on real hardware.

### Tier 3: Separate Test User (full session testing)

For testing with the real KMS/DRM backend, use a dedicated test user account on a separate TTY. Your main session remains untouched and recoverable.

**One-time setup:**

```bash
sudo useradd -m -s /bin/bash testcomp
sudo passwd testcomp
```

**Test cycle:**

```bash
# 1. Build on your main account
cargo build --release

# 2. Copy the binary where the test user can access it
sudo cp target/release/cosmic-comp /usr/local/bin/cosmic-comp-fork

# 3. Switch to a different TTY
#    Ctrl+Alt+F3

# 4. Log in as testcomp, launch the compositor
#    (exact launch command depends on session setup)

# 5. If it crashes: Ctrl+Alt+F1 returns to your main session
```

See [SAFETY.md](SAFETY.md) for detailed recovery procedures.

## Project Structure

```
cosmic-comp-fork/
├── src/                    # cosmic-comp source (do not modify without plan)
├── cosmic-comp-config/     # shared configuration crate
├── README.md               # this file
├── SAFETY.md               # compositor development safety guidelines
├── ARCHITECTURE.md         # technical overview and extension targets
├── DEVELOPMENT.md          # phase-based development roadmap
├── .cursor/
│   ├── rules/              # Cursor AI rules for safe compositor development
│   ├── agents/             # sub-agent briefings and phase templates
│   ├── plans-archive/      # completed/superseded plans
│   └── agents-archive/     # completed/superseded agent briefings
└── ...                     # upstream cosmic-comp files (Cargo.toml, etc.)
```

## Project Archives

Historical plans and sub-agent definitions are archived in:

- `.cursor/plans-archive/` -- completed phase plans
- `.cursor/agents-archive/` -- completed sub-agent briefings

These are read-only snapshots for long-term reference and onboarding.

## Upstream

This fork tracks [pop-os/cosmic-comp](https://github.com/pop-os/cosmic-comp) master. The base commit is `f0b54315`. All changes are additive protocol extensions and do not modify upstream behavior for unrelated functionality.

## License

Same as upstream: GPL-3.0-only.
