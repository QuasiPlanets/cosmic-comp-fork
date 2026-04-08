# Phase 3 Sub-Agent: Integration Testing (cosmic-layout-presets)

## Pre-Work: Re-Read All Project Documents

Before any code changes, re-read in full:

- [README.md](../../README.md)
- [SAFETY.md](../../SAFETY.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md) (especially **Client Requirements — cosmic-layout-presets**, **Gap Table**, and **Extension Targets**)
- [DEVELOPMENT.md](../../DEVELOPMENT.md) (especially **Phase 1 Summary** and **Phase 2 Summary** — protocol versions, Shell methods, LayoutMeta / info events)
- [.cursor/rules/core-enforcement.mdc](../rules/core-enforcement.mdc) (all rules: safety-first, official crates only, one-todo-at-a-time, re-read requirement, **Archive Rule**)

If any clarification is needed about Phase 1 or Phase 2 compositor/protocol decisions, ask the existing **Phase1-Protocol-Extension** sub-agent (agent ID `22fb0a47-5ddc-41ba-b032-1de309d79441`) or **Phase2-Shell-Implementation** sub-agent (agent ID `422b88d1-42de-48cd-8ede-7812a7533d9e`).

After re-reading **ARCHITECTURE.md** and the current **DEVELOPMENT.md**, proceed with implementation.

## Approved Plan

Implement **exactly** the approved Phase 3 plan:

- Active plan file (source of truth for todos and steps):  
  `~/.cursor/plans/phase_3_integration_testing_f407e7bd.plan.md`  
  (same content as the Phase 3 Integration Testing plan: client deps, actions, capture/apply, info events, Tier 2 verify.)

**Client working directory (this machine — use only this clone; do not `git clone` cosmic-layout-presets):** `/home/tes/QuasiPlanetsRepos/cosmic-layout-presets`

**Compositor** (read-only for Phase 3 code; build Tier 2 from): `/home/tes/cosmic-comp-fork`

GitHub references: [cosmic-layout-presets](https://github.com/QuasiPlanets/cosmic-layout-presets), [cosmic-protocols-fork](https://github.com/QuasiPlanets/cosmic-protocols-fork), [cosmic-comp-fork](https://github.com/QuasiPlanets/cosmic-comp-fork) branch `phase-1-protocol-extension`.

## Objective

Update the **cosmic-layout-presets** client to consume the Phase 1–2 protocol extensions: new manager requests (`set_position`, `set_size`, `set_floating`, `set_tiled`, `set_stacking_order`), new info state (`tiled` / `floating`) and `stacking_order`, with **end-to-end** capture → rearrange → apply verification (Tier 2 nested winit minimum).

## Dependency Rule

**No new third-party crates.** Only `cosmic-layout-presets`, **patched** [cosmic-protocols-fork](https://github.com/QuasiPlanets/cosmic-protocols-fork) / `cosmic-client-toolkit`, and existing dependencies. Pin versions; no wildcards in `Cargo.toml`.

## Scope and Boundaries

### In scope (Phase 3)

- Work only in **`/home/tes/QuasiPlanetsRepos/cosmic-layout-presets`** (typical files: `Cargo.toml`, `src/wayland_handler.rs`, `src/preset_session.rs`, `src/config.rs`). Do **not** clone the client repository; use the existing tree.
- Point the client at **cosmic-protocols-fork** via `[patch]` (see approved plan).
- Extend `ToplevelAction` and `handle_toplevel_action`; update capture/apply; verify `ToplevelInfoHandler` path for new state/events.
- **`cargo check`** after each logical step; **`cargo clippy --all-features -- -D warnings`** after each **major** step (if the crate has no `all-features`, use the project’s equivalent documented feature set or `cargo clippy -- -D warnings` and state why).
- **Show clear diffs** (or equivalent file-by-file summary) for **every changed file**.
- **One todo at a time** — complete `p3-client-deps`, then `p3-action-variants`, then `p3-capture-update`, then `p3-apply-update`, then `p3-info-events`, then `p3-verify`. Do not start the next todo until the current one compiles and is complete.

### Out of scope

- **No changes to cosmic-comp-fork** (compositor). Phase 3 is **strictly client-side**.
- No new protocol XML in Phase 3 (protocols fork is read-only for integration).
- Do **not** remove legacy workarounds entirely — keep `repeat_unset_sequence_for_floating_or_fullscreen_mismatch`, activation replay delay, `APPLY_POST_LAUNCH_WAIT_MAX` as **fallbacks** until Phase 4 (transactions). Prefer new protocol requests when capabilities allow.

## Safety and Testing

- **Tier 1:** `cargo check` + clippy as above; required frequently.
- **Tier 2:** Nested winit — build/run **fork** compositor, point client at `WAYLAND_DISPLAY` of nested session; exercise capture → rearrange → apply. See **SAFETY.md** and the approved plan Part F.
- **Tier 3:** Optional/recommended for real KMS/multi-monitor; not a substitute for Tier 2 for this phase.
- **No `unwrap()` / `panic!()`** in new client paths; match existing client error style (`if let`, logging).

## Success Criteria (align with approved plan)

- Real **Tiled** / **Floating** capture (not inferred only).
- Real **stacking_order** from protocol (not activation-only proxy).
- Restore **position/size** for floating windows; **tiled/floating** and **stacking** behavior per Phase 2 semantics (including capability checks and graceful degradation).
- Round-trip fidelity per Tier 2 procedure; **`cargo clippy` clean** (`-D warnings`).
- **Zero compositor diffs** in Phase 3.

## Post-Completion (main agent — do not do as sub-agent)

Per **Archive Rule** in `core-enforcement.mdc`: main agent archives the Phase 3 plan to `.cursor/plans-archive/phase-3-integration-testing.md` and appends **DEVELOPMENT.md** with Phase 3 completion / archival notes.
