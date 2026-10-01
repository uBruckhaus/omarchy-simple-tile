# Simple Tile

![Simple Tile — a little room to focus](docs/banner.svg)

**Give your windows room. Make every workspace your own.**

Simple Tile brings workspace limits, visual layout presets, and saved app
workspaces to your Omarchy bar. Keep everyday windows comfortably tiled, or
save a workspace for coding, research, and communication and bring it back
when you need it.

- **Room to focus:** set a limit of 1–4 windows globally or per workspace.
  New overflow windows move forward to a workspace with room; focus follows.
- **Layouts at a click:** side-by-side, stacked, master-left, master-right,
  columns, and a 2×2 grid. Native mode removes limits and automatic overflow.
- **Your apps, your arrangement:** save an App Preset with window geometry
  and app icons, launch missing apps, and rebuild the saved layout.
- **Restore on your terms:** move conflicting windows, close them, keep them
  floating, or cancel. Optional auto-move makes repeat restores quicker.
- **Ready after login:** optionally restore saved workspaces once per
  Hyprland session.
- **At home in Omarchy:** theme-aware controls, workspace cards, contextual
  right-click help, and a right-click pause button on the bar.

See the [user manual](MANUAL.md) for controls and workflows, and the
[0.2.3 release notes](CHANGELOG.md) for what changed.

## Install

Requires **Omarchy with the Quickshell plugin system**, Python 3.10+, and
**Hyprland 0.56.2 with its Lua dispatch API**. Older Waybar-based Omarchy
installations are not supported. This is an early `0.2.3` release.
App launching uses saved argument lists or `uwsm-app` for desktop files;
PyGObject/GioUnix is an optional fallback. No pip installation is required.

```sh
omarchy plugin add https://github.com/uBruckhaus/omarchy-simple-tile.git
omarchy plugin enable ubruckhaus.simple-tile
```

The widget appears on the right of the bar. Click **▦** to open settings.
Right-click to pause or resume. In the popup, use Tab to navigate controls,
Enter or Space to activate them, and Escape to close.

```sh
omarchy bar move ubruckhaus.simple-tile --section right
omarchy plugin disable ubruckhaus.simple-tile
omarchy plugin remove ubruckhaus.simple-tile
```

## How overflow works

Only newly opened, mapped, visible tiling windows trigger a move. Floating
windows, fullscreen windows, scratchpads, and newly opened tab-group members
are left alone. Changing the limit does not redistribute existing windows. Selecting a
geometric preset can rearrange the current workspace.

**Manual moves override the limit:** Manually moving a window to another
workspace (for example, using `Super+Shift+2` or dragging) intentionally
overrides the workspace window limit without being redirected. This is fully
intended: Simple Tile manages incoming overflow when windows first open,
but always respects your manual arrangements and never fights your manual moves.

Simple Tile scans higher-numbered workspaces on the source monitor for room.
Each workspace respects either its specific limit or the global default limit.
If candidate workspaces on that monitor are full, it chooses a new number after
that monitor's highest workspace, skipping IDs already used on other monitors.
It targets the new window by address, so changing focus cannot cause a
different window to be moved.

Hyprland remains responsible for creating new workspaces and applying your
workspace rules, including explicit monitor assignments. Named and special
workspaces are excluded. The limit counts visible tiled clients, not layout
slots; tabbed/grouped layouts are deliberately not automatically redistributed.

## Presets vs App Presets

Simple Tile supports two modes for your workspaces:

- **Presets (Default):** Set a window limit (1–4 windows) globally or per workspace, and choose from geometric layout presets (Side-by-Side, Stacked, Master-Left, Master-Right, Columns, 2×2 Grid, or Native). When a new window opens and exceeds the limit, Simple Tile automatically moves it to the next workspace on your monitor.
- **App Presets:** Select any workspace, open and arrange your apps according to your preferences, then click **Save App Preset**:
  - **Layout Snapshots:** Captures window geometry, count, and arrangement.
  - **App Icons:** Optionally save the opened applications and display their real application icons directly inside the workspace card in the bar popup.
  - **Restore / Launch Apps:** Click **Restore App Preset** to launch missing apps, place them on the saved workspace, and rebuild the saved tile positions and proportions using native dwindle tiles. Floating windows regain their saved position and size. Each saved window has its own app launch information, including multiple windows of one app.
  - Existing windows are matched by app class and, where possible, title. A uniquely matching app on another workspace can be moved back unless it belongs to another saved layout. Apps that cannot open another window report a timeout.
  - Restoration supports ungrouped, non-fullscreen rectangular tiling arrangements. The restore dialog lets you move, close, or float conflicting windows before restoring. App content (documents, terminal commands, browser tabs) is not restored. Changed monitor geometry and gaps can affect exact pixel sizes.
  - **Autostart:** Optionally flag the workspace to automatically restore its saved windows once per Hyprland session. Multiple bars and shell reloads do not duplicate startup launches; failed restores can be retried with Restore.
  - Workspaces using App Presets are never disrupted by automatic overflow moves.

## Settings

Use the popup to change the global default, customize individual workspace
limits and layouts, and save or restore App Presets. Workspace cards are
paged as **1–4** and **5–8**. Settings are stored on the widget's bar entry in
`~/.config/omarchy/shell.json` and shared across monitors.

Pausing keeps the control visible; disabling the plugin removes it.
The prototype's separate `simple-tile/config.json` is no longer used.

## Development

```sh
python3 -m unittest discover -s tests -v
node --test tests/*.js
omarchy plugin validate .
```

`BarWidget.qml` owns the interface and subscribes to Quickshell's Hyprland
`openwindow` events. A short-lived Python helper reads the saved settings,
queries clients/workspaces, and moves only the overflowing window. Calls are
serialized with a runtime file lock, including calls from multiple bar instances.
The helper verifies that Hyprland actually moved the window before reporting success.

To inspect a decision without moving anything, supply an address from
`hyprctl clients -j`:

```sh
python3 simple_tile.py --window 0xYOUR_ADDRESS --dry-run
```

The plugin must be enabled in the bar configuration for the helper to act.
Failures show an **!** in the bar and a message in the popup; details go to the
Omarchy shell log. The helper's JSON output is also useful for debugging.

See [the prototype review](docs/REVIEW.md) for the bugs addressed and
[release checks](docs/RELEASING.md) for the remaining marketplace work.

## License

MIT © 2026 Uwe Bruckhaus

The plugin popup uses fixed original Omarchy styling, independent of desktop themes. Click **User Manual** for integrated guidance.
