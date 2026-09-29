# Simple Tile — marketplace description

**Give your windows room. Make every workspace your own.**

Simple Tile brings comfortable tiling and repeatable workspaces to your Omarchy
bar. Choose how many windows belong together, pick a layout, and let newly
opened overflow windows move to the next workspace with room. Your manual
window moves always take precedence.

Switch to **App Presets** when a workspace needs a familiar set of tools.
Arrange your editor, terminal, browser, or communication apps, then save their
layout. Restore launches missing apps and rebuilds supported tile arrangements;
optional session autostart brings your saved workspaces back after login.

- **Window limits:** 1–4 windows, globally or per workspace.
- **Visual layouts:** side-by-side, stacked, master-left, master-right, columns,
  and a 2×2 grid; Native mode has no limit or automatic overflow.
- **Saved app workspaces:** layout snapshots, real app icons, and support for
  multiple saved windows of one app.
- **Restore choices:** move conflicting windows, close them, keep them floating,
  or cancel. Enable auto-move for quicker repeat restores.
- **Workspace protection:** App Preset workspaces are excluded from automatic
  overflow routing, including saved workspaces that are not currently open.
- **Native controls:** theme-aware workspace cards, right-click help, and
  instant pause/resume from the bar.

Restoration supports ungrouped, non-fullscreen rectangular tiled arrangements
and saved floating geometry. It does not restore app content such as documents,
terminal commands, or browser tabs. Monitor geometry and gaps can affect exact
pixel sizes, and apps that cannot open another window may time out.

## Listing metadata

- Plugin ID: `ubruckhaus.simple-tile`
- Version: `0.2.0`
- Author: Uwe Bruckhaus
- Category: Desktop
- Tags: workspaces, hyprland, bar
- License: MIT
- Repository: https://github.com/uBruckhaus/omarchy-simple-tile
- Listing: https://omarchyplugins.com/plugin.html?id=ubruckhaus.simple-tile

## Install

Requires Omarchy with the Quickshell plugin system, Python 3.10+, and Hyprland
0.56.2 with its Lua dispatch API. App launching uses saved argument lists or
`uwsm-app`; PyGObject/GioUnix is an optional fallback.

```sh
omarchy plugin add https://github.com/uBruckhaus/omarchy-simple-tile.git --enable
```

See the [README](README.md) and [user manual](MANUAL.md) for usage and removal.

## Publication

This plugin is already listed. Submit updates through the marketplace's
[verification form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml)
using **Verify and publish a newer upstream commit** and the full release SHA.
The previous snapshot remains listed until marketplace maintainers approve and
publish the update. Prior verification does not cover this new release.
