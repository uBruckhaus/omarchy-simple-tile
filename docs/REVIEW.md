# Prototype review

Two versions were found locally: a standalone script and a later copy in the
Omarchy plugin directory. Neither had a manifest or a loadable QML entry point.
The original files are preserved outside this repository.

| Finding | Resolution |
| --- | --- |
| No Omarchy manifest or shell entry point | Validated manifest and native bar widget |
| D-Bus startup used nonexistent Gio methods | Removed the separate tray implementation |
| Invalid StatusNotifier tooltip and dbusmenu signatures | Use Omarchy's own popup controls |
| `count < cap` moved the window at exactly the limit | Only move when `count > cap`; regression test |
| Workspace dispatcher switched workspaces instead of moving a window | Use Lua window move with an explicit address; verify result |
| Focus-based dispatch could affect another window | No focus operation; address-targeted move |
| Only workspace `-1` was excluded | Ignore all non-positive workspace IDs |
| New workspace ID could belong to another monitor | Skip globally occupied IDs |
| Socket handling lost partial events and did not recover reliably | Subscribe to Quickshell's existing Hyprland connection |
| Duplicate processing across monitors | Runtime lock and fresh state for each event |
| Unbounded/stale daemon lifecycle and PID files | No daemon or PID files |
| Disabled icon made transparent pixels opaque | Native theme-aware widget with dimmed pause state |
| Cap 6 and 7 missing from settings | All limits from 1 through 8 |

The original hand-rendered icon concept is retained as a tile/grid motif. The
repository adds a vector banner, installation instructions, regression tests,
and GitHub Actions. Desktop behavior follows the installed Omarchy UI contracts
and Hyprland 0.56.2's address-targeted Lua dispatcher.

References: [Hyprland dispatchers](https://wiki.hypr.land/configuring/core/dispatchers/)
and [the 0.56.2 dispatcher implementation](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/lua/bindings/LuaBindingsDispatchers.cpp).
