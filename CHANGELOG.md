# Release notes

## 0.5.2 — 2026-10-21

- Security (marketplace review of 0.5.1): a window that matched no installed launcher saved its class as the launcher name, and Restore joined that name onto the launcher folders, so an absolute or `../` class could reach a `.desktop` file outside them and `uwsm-app` or Gio would start it. A sandboxed app with a data folder the host can see could plant such a file. Now a launcher is only ever taken from the installed launchers themselves: a saved path must be one of them, a saved name must be one file name (no `/`, no leading dot) that one of them has, and an unmatched window saves no launcher name at all. Presets saved before keep working for apps with a real launcher; a window without one is reported as not restorable, as before.

## 0.5.1 — 2026-10-21

- Fix: the helper's `--clear-app-preset` and `--clear-all-app-presets` commands crashed before doing anything (they passed a name to the runtime lock, which takes none); their tests had replaced the lock with a mock. They now use the shared lock, and `shell.json` is replaced through a private temporary file that keeps its permissions, instead of a fixed `shell.tmp` name. The popup does not use these commands.

## 0.5.0 — 2026-10-21

- New **Scrolling** preset beside **Floating**: windows line up as full-height columns on a strip that scrolls sideways; no window limit or automatic overflow. New bar icon, card preview and texts in all 8 languages.
- **Omarchy 4.5 workspace modes** (Super + L): Floating and Scrolling now set the workspace's own Omarchy mode, saved by Omarchy in `~/.local/state/omarchy/workspace-layouts/<workspace>.lua`, so the Omarchy bar, dock, titlebars and Super + L agree with the popup. A tiling preset, a limit or Native tiles such a workspace again.
- Workspaces without a preset of their own (or Native) show the mode set with Super + L; checked at start, when the popup opens, on workspace changes and after a config reload. At shell start, presets set in Workspace Presets win and Omarchy's modes are lined up with them.
- Windows opening on a workspace Omarchy floats or scrolls are never moved on or tiled.
- On Omarchy before 4.5, Floating works as before and Scrolling uses Hyprland's scrolling layout.

## 0.4.2 — 2026-10-20

- Security (marketplace review of 0.4.1): **Save App Preset** no longer records a window's own `/proc/<pid>/cmdline` as its launch command, and restore never runs one saved by an older version. A sandboxed app could put a host program there, which Restore or the session autostart would then have run outside its sandbox. Missing apps start from their installed launcher; a window without one is reported as not restorable (new text in all 8 languages). The window class is no longer looked up on `PATH` either. A terminal's foreground command is still saved, but only from a terminal emulator installed under `/usr` in this session's own mount namespace, and restored only when it starts with that terminal.

## 0.4.1 — 2026-10-19

- Tests only: the JavaScript tests give the functions they lift out of `BarWidget.qml` the plugin's English texts (`tests/english.js`), so they pass again; they had failed since 0.3.0 added the translations. No change to the plugin itself.

## 0.4.0 — 2026-10-19

- New **Information** page behind the **ⓘ** button beside the gear: a card for each of the author's other marketplace plugins; a click opens its marketplace page in the browser. **← Back**, Backspace or Esc returns.

## 0.3.2 — 2026-10-17

- New **Floating** preset.

## 0.3.1 — 2026-10-17

- Works with Qt 6.12: the shell palette is referenced as `Commons.Color`, because Qt 6.12 adds its own `Color` type that hid it and left panels and buttons without colours. Also works on Qt 6.11.

## 0.3.0 — 2026-10-13

- Eight built-in interface languages (English, German, French, Spanish, Italian, Portuguese, Dutch, Polish); the system language is used unless another one is picked.
- New settings page behind the gear (⚙): language, right-click help hints and auto-move switches; **← Back**, Backspace or Esc returns.
- The long built-in user manual was removed from the popup; MANUAL.md stays in the repository.

## 0.2.8 — 2026-10-10

- Simple Tile is now called **Workspace Presets**: it does more than tiling (window limits, layouts and App Presets). The plugin ID, install path and saved settings stay the same.

## 0.2.7 — 2026-10-04

- Rebuild the preview image from real screenshots of the Presets and App Presets tabs.
- Lead the manifest, README and marketplace descriptions with Presets and App Presets.
- Keep the three layout buttons for a 3-window workspace inside the panel; the last one ("Columns") ran past its right edge.

## 0.2.6 — 2026-10-02

- Render restore-conflict window titles as plain text so webpage title markup cannot load remote images.
- Render saved app names and restore failure/status messages as plain text as well.

## 0.2.5 — 2026-10-01

- Add One Window Tiling for workspaces with a one-window limit, including automatic overflow.
- Clear all layout and App Presets immediately with one button, including custom limits and autostart settings; open apps stay open.
- Use gray workspace preview frames and a small dot to indicate the active workspace independently of configuration selection.
- Enable autostart by default for newly saved App Presets while preserving explicit choices.
- Treat unchanged settings as successful saves instead of showing a false warning.
- Add workspace and global preset management controls and improve popup interaction.
- Load the shared layout script as a QML library and adapt the JavaScript test loader.

## 0.2.4 — 2026-10-01

- Enhanced bar icon with `ShellUi.BarIconButton` and 5 distinct visual states:
  1. **Disabled**: Dimmed outline tiles with pause bars (`||`).
  2. **Enabled (no preset or app preset defined)**: Clean neutral outline tiles.
  3. **Enabled with defined presets**: Solid filled geometry tiles representing the active layout.
  4. **Enabled with App Preset (Autostart OFF)**: Layout tiles with an open ring indicator (`○`) in dynamic theme accent color.
  5. **Enabled with App Preset (Autostart ON)**: Layout tiles with a solid filled dot indicator (`●`) in dynamic theme accent color.
- Automatically ensures Simple Tile is enabled by default on session start and after system reboot.
- Comprehensive tooltips reflecting the active icon mode and autostart state.

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
