# Release notes

## 0.2.3 — 2026-10-01

- Automatically ensures Simple Tile is enabled by default on session start and after system reboot (`Component.onCompleted` initialization).
- Prevents temporary in-session pauses from permanently keeping the plugin disabled across reboots.

## 0.2.2 — 2026-10-01

- Stable popup layout dimensions and themed manual headings.
- Full support for right-click help and keyboard navigation in settings.

Includes all 0.2.0 features below. Fixes a workspace-capture test that depended
on the developer’s desktop configuration; it now uses isolated settings and
works on clean CI runners. Runtime behavior is unchanged from 0.2.0.

## 0.2.0 — 2026-09-29

**Give your windows room. Make every workspace your own.**

Simple Tile now combines automatic workspace overflow with visual layout
presets and saved app workspaces, all from the Omarchy bar.

- Choose side-by-side, stacked, master-left, master-right, columns, or 2×2 grid
  layouts. Native mode disables window limits and automatic overflow.
- Save App Presets with window geometry and app icons; restore missing apps
  and supported tiled or floating arrangements, including multiple app windows.
- Optionally restore saved workspaces once per Hyprland session.
- Handle restore conflicts by moving, closing, or floating extra windows, or
  cancel. Optional auto-move streamlines repeated restores.
- Browse workspace cards in pages 1–4 and 5–8 and use contextual right-click help.
- Keep saved App Presets when switching modes; remove apps from snapshots
  without closing live windows.
- Improve Chrome/Chromium multi-window restoration and close-confirmation handling.
- Exclude App Preset workspaces from incoming overflow, including inactive saved
  workspaces. Preserve manual window moves and the existing lock-file safety fix.

Restoration does not restore documents, terminal commands, or browser tabs.
Grouped/fullscreen and non-rectangular tiled layouts are unsupported; monitor
geometry and gaps can affect exact pixel sizes.

Validation: 80 Python regression tests, both JavaScript test files, and local
Omarchy manifest validation. Full multi-monitor desktop acceptance testing is
not part of this release check.
