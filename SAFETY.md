# Safety Guidelines for Compositor Development

## Why This Is High-Risk

A Wayland compositor is not a normal application. It **is** the display server. It owns:

- Every pixel on your screen
- All keyboard and mouse input
- The GPU and display hardware (via DRM/KMS)
- The session seat (via libseat)

If the compositor crashes, panics, deadlocks, or enters an invalid state, you get a **black screen with no input**. You cannot open a terminal, switch windows, or do anything within that session. The only recovery is switching to a different TTY (if the kernel VT subsystem still works) or rebooting.

This is fundamentally different from crashing a normal application. Treat compositor changes with the same caution you would treat kernel module changes.

## The Golden Rule

**Never replace your daily-driver compositor with an untested build.**

Your main user account's session compositor must always be the stable, upstream binary. All testing happens in isolated environments that cannot damage your working session.

## Three-Tier Testing Strategy

### Tier 1: Build Only (zero risk)

Run `cargo check` and `cargo build` on your main user account. This compiles the code but does not run it as a compositor. Completely safe.

```bash
cd ~/cosmic-comp-fork
cargo check            # type checking only, fastest feedback
cargo build            # debug build
cargo clippy           # lint checks
cargo build --release  # optimized build for later testing
```

**When to use:** Every code change. This is your primary feedback loop.

### Tier 2: Nested Winit (low risk)

Run the compositor inside a window on your existing Wayland session using Smithay's winit backend. The nested compositor appears as a regular window -- if it crashes, only that window closes. Your main session is unaffected.

```bash
COSMIC_BACKEND=winit ./target/debug/cosmic-comp
```

The nested compositor opens its own `WAYLAND_DISPLAY` socket. Point test clients at it:

```bash
WAYLAND_DISPLAY=wayland-1 your-test-client
```

**Limitations:**
- No multi-monitor support
- No real DRM/KMS -- rendering goes through the parent compositor
- Input handling differs slightly from native
- Some protocol features may behave differently

**When to use:** After Tier 1 passes. Good for verifying protocol changes, testing client-compositor communication, and checking basic layout behavior.

### Tier 3: Separate Test User on a Different TTY (full testing)

For testing with real hardware (DRM, multi-monitor, actual input devices), use a dedicated test user account on a separate TTY. Your main session on TTY1/TTY2 remains running and untouched.

#### One-Time Setup

Create the test user:

```bash
sudo useradd -m -s /bin/bash testcomp
sudo passwd testcomp
```

Ensure the test user can access the GPU and seat. On most systems with systemd-logind/seatd, logging in on a TTY handles this automatically. If needed:

```bash
sudo usermod -aG video testcomp
sudo usermod -aG input testcomp
```

#### Test Cycle

```bash
# 1. Build on your main account (Tier 1)
cd ~/cosmic-comp-fork
cargo build --release

# 2. Copy the binary to a shared location
sudo cp target/release/cosmic-comp /usr/local/bin/cosmic-comp-fork

# 3. Switch to a different TTY
#    Press Ctrl+Alt+F3

# 4. Log in as testcomp

# 5. Launch the compositor
#    The exact command depends on your session setup.
#    A minimal launch might be:
/usr/local/bin/cosmic-comp-fork

#    Or with the full COSMIC session (if cosmic-session is installed):
#    COSMIC_COMP=/usr/local/bin/cosmic-comp-fork cosmic-session

# 6. Test your changes

# 7. Exit the test session (log out or Ctrl+C the compositor)

# 8. Switch back to your main session
#    Press Ctrl+Alt+F1 (or F2, whichever TTY your main session is on)
```

**When to use:** Before considering any change "done." Required for changes that touch rendering, input handling, session management, or DRM/output configuration.

## Recovery Procedures

### Compositor crashed on test TTY

1. Press **Ctrl+Alt+F1** to switch back to your main session TTY.
2. Your main session should be exactly as you left it.
3. Fix the issue, rebuild, try again.

### Test TTY is unresponsive (no input)

1. Try **Ctrl+Alt+F1** -- the kernel VT switch often still works even when the compositor is hung.
2. If that fails, SSH in from another machine: `ssh tes@your-machine`, then `sudo kill -9 $(pgrep cosmic-comp-fork)`.
3. As a last resort, use SysRq: **Alt+SysRq+K** (SAK) kills all processes on the current VT.
4. If all else fails, reboot. Your main account is unaffected.

### Main session is fine but test user's home is messy

The test user's home directory may accumulate state from crashed sessions. Periodically clean it:

```bash
sudo rm -rf /home/testcomp/.cache/cosmic-comp
sudo rm -rf /home/testcomp/.local/state/cosmic-comp
```

## Things You Must Never Do

1. **Never replace `/usr/bin/cosmic-comp` on your main account with an untested build.** If the build is broken, your next login will fail to start a session.

2. **Never run a debug build as your session compositor.** Debug builds have `debug_assert!` and other panic paths enabled. A panic in a compositor is a black screen.

3. **Never force-push to the `master` branch.** The master branch must always build and match a known-good state.

4. **Never skip the test-user step for changes that touch:**
   - Rendering or damage tracking
   - Input handling or seat management
   - Session startup/shutdown
   - DRM/KMS output configuration
   - Protocol dispatch or global registration

5. **Never run the compositor as root.** It should run as a normal user with seat access via logind/seatd.

6. **Never add untrusted or random crate dependencies.** The compositor runs with full access to your GPU, input, and display. Every dependency is part of the trusted computing base.

## Pre-Commit Safety Checklist

Before committing any change:

- [ ] `cargo check` passes
- [ ] `cargo clippy` has no new warnings
- [ ] Tier 2 (nested winit) tested if the change affects protocols or layout
- [ ] Tier 3 (test user) tested if the change affects rendering, input, or session
- [ ] No unrelated files modified
- [ ] Commit message accurately describes the change
- [ ] No secrets, credentials, or user-specific paths in the commit
