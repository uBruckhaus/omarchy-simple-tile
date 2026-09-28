# Marketplace Publication Listing: Simple Tile

This document contains the ready-to-use copy, metadata, and feature breakdown for submitting **Simple Tile** to the [Omarchy Plugin Marketplace](https://plugins.omarchy.org) and `omacom/omarchy-plugin-marketplace`.

---

## 📋 Marketplace Metadata Sheet

- **Plugin ID**: `ubruckhaus.simple-tile`
- **Display Name**: `Simple Tile`
- **Version**: `0.1.0`
- **Author**: `Uwe Bruckhaus`
- **Category**: `Desktop` *(Alternative: `Widgets`)*
- **Tags**: `Workspaces`, `Hyprland`, `Bar`
- **Repository**: `https://github.com/uBruckhaus/omarchy-simple-tile`
- **License**: `MIT`
- **Default Bar Section**: `right`

---

## 🏷️ Short Description (Tagline)

> Give your windows room. Calm, per-workspace window limits and automatic overflow management for Omarchy, with full respect for manual window moves.

---

## 📝 Full Marketplace Description

**Simple Tile** brings calm and order to your Omarchy desktop by preventing workspaces from becoming overcrowded. If you prefer tiled windows without squeezing four or five apps onto a single monitor screen, Simple Tile automatically moves overflow windows to the next available workspace as they open.

Set a global default limit (such as 2 windows per workspace), or tailor individual workspace capacities to your workflow—for example, a strict single-window focus limit on Workspace 1 for your editor, and a generous 4-window limit on Workspace 2 for communication and tools.

Simple Tile is designed to work seamlessly with your desktop habits, never fighting you for control:

- **Manual Moves Always Take Precedence**: Manually moving windows with your compositor keybindings (e.g., `Super+Shift+2`) or mouse dragging intentionally overrides the window limit. Simple Tile handles incoming overflow when windows first open, but always honors your explicit layouts.
- **Approved & Secure Startup Architecture**: No background Python daemons, no tray polling loops, and no persistent PID files. Simple Tile uses Quickshell's native event hooks to invoke a short-lived helper via direct `argv` vectors (zero shell interpretation), serialized via user-isolated runtime locks in `$XDG_RUNTIME_DIR`.
- **Native Theme Harmony**: Built with native Quickshell components that automatically follow your active Omarchy theme colors, fonts, and border styles.

---

## ✨ Feature Highlights

- ▦ **Native Quickshell Bar Widget**: Displays a clean status-bar icon with right-click instant pause/resume, live tooltip showing active workspace limit, and one-click access to settings.
- 📐 **Per-Workspace Window Caps**: Customize limits from 1 to 8 windows for each individual workspace (WS 1–10) or rely on a unified global default.
- 🗂️ **Visual Desktop Workspace Cards**: Clear, labeled workspace cards with live active-desktop indicator dots and visual cap badges (`▦ 2`, `▦ 4`).
- 🔄 **Intelligent Forward Overflow Routing**: Overflow windows scan forward on the current monitor to find the nearest workspace with room, avoiding cross-monitor collisions and preserving monitor workspace assignments.
- 🛡️ **Respects Window Types**: Floating windows, full-screen windows, scratchpads, and deliberate tabbed window groups are never automatically moved.
- 🚶 **Optional Follow Mode**: Choose whether your focus follows the moved window to the new workspace or stays on your current desktop.
- 🔒 **Secure Zero-Daemon Engine**: Runs on standard system Python with no pip or PyGObject dependencies. Executes with direct argument vectors, safe address sanitization, and strictly user-isolated file locks.

---

## ⌨️ Controls & Keyboard Shortcuts

| Shortcut / Interaction | Function |
| :--- | :--- |
| **Click ▦ on status bar** | Open or dismiss the Simple Tile settings popup |
| **Right-Click ▦ on status bar** | Instantly pause or resume automatic window tiling |
| **Tab / Shift+Tab** | Navigate through popup controls and workspace cards |
| **Space / Enter** | Toggle settings, select workspace, or activate limit |
| **Escape** | Close settings popup |
| **`Super+Shift+[1-9]`** | Manually move window to workspace (deliberately bypasses tiling limit) |

---

## 💻 Installation

```bash
omarchy plugin add https://github.com/uBruckhaus/omarchy-simple-tile.git --enable
```

To remove or disable:

```bash
omarchy plugin disable ubruckhaus.simple-tile
omarchy plugin remove ubruckhaus.simple-tile
```
