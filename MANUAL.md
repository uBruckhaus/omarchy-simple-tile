# Simple Tile — User Manual

Simple Tile provides smart, calm window management for Hyprland on Omarchy. It prevents workspaces from becoming cluttered by giving your windows room to focus.

---

## 1. Core Concepts

Simple Tile operates in two distinct modes for your workspaces:

| Mode | Purpose | Window Overflow Behavior |
| :--- | :--- | :--- |
| **Presets** *(Automatic)* | Dynamic daily workflow with geometric layouts. | When the window limit is reached, newly opened windows **automatically move** to the next free workspace. |
| **App Presets** *(Manual)* | Dedicated app suites (e.g. coding, communications, media). | **Automatic moves are disabled**. Saved layouts are retained until you save again; restore rebuilds supported arrangements. |

> **User Precedence**: Manually moving windows with keybindings (e.g. `Super+Shift+2`) intentionally overrides window limits. Simple Tile only routes *newly launched* windows on overflow and always follows the moved window to its new workspace.

---

## 2. Workspaces & Limits

- **Workspace Navigation**: Use the `1 – 4` and `5 – 8` switcher to flip between workspace groups.
- **Selecting Scope**:
  - Click any **Workspace Card** (1 to 8) to customize limits and layouts for that specific workspace.
  - Click **All Workspaces** to configure the global default window limit (1 to 4) applied to all workspaces without custom overrides.
- **Setting Limits**: Choose `1`, `2`, `3`, or `4` windows per workspace. Setting `2` windows is recommended for split-screen coding and research.

---

## 3. Presets (Dynamic Tiling)

When a workspace is in Presets mode, you can select how your windows arrange themselves:

- **2 Windows**:
  - `⬌ Side-by-Side`: Two equal vertical columns (left and right).
  - `⬍ Stacked`: Two equal horizontal rows (top and bottom).
- **3 Windows**:
  - `◨ Master Left`: 1 large master window on the left, 2 stacked on the right.
  - `◧ Master Right`: 1 large master window on the right, 2 stacked on the left.
  - `||| Columns`: 3 side-by-side vertical columns across the screen.
- **4 Windows**:
  - `▦ 2×2 Grid`: Balanced four-quadrant 2×2 grid layout.
  - `◨ Master Left`: 1 large master on the left, 3 stacked on the right.
  - `◧ Master Right`: 1 large master on the right, 3 stacked on the left.
  - `|||| Columns`: 4 side-by-side vertical columns across the screen.
- **✕ No Preset (Native)**: Uses Hyprland's native tiling with **no window limit and no automatic overflow**. None of the maximum-window buttons is selected. Choose a numbered limit or geometric preset to resume limited automatic tiling.

---

## 4. App Presets (Saved Geometry & Autostart)

Click **App Presets** to immediately enable manual editing on the selected workspace, whether or not either kind of preset has been saved. Open, close, and arrange windows freely. These changes do not overwrite the saved app preset until you click **Save App Preset**.

Click **Presets** to resume the configured geometric layout (or the default) and automatic overflow. This keeps the saved app preset and does not restore its apps.

App Presets let you turn any workspace into a dedicated, persistent workstation:

1. **Arrange your Apps**: Open your desired applications and position them on the workspace (tiled or floating).
2. **Save Preset**: In the popup panel under **App Presets**, click **Save App Preset**. Simple Tile captures window coordinates, sizes, desktop entries, and commands.
3. **Restore Preset**: Click **Restore App Preset** anytime. Simple Tile relaunches any missing applications and rebuilds their saved tile arrangement and proportions. Floating windows regain their saved position and size.
4. **Remove Apps from Preset**: Click the `✕` on an application's chip to remove it from the preset (this does not close your open window).
5. **Autostart on Login**: Turn on **Autostart on session startup** to launch your saved workstation automatically whenever you log into Omarchy.

---

## 5. Conflict Resolution on Restore

When you click **Restore App Preset** on a workspace that already has open windows, Simple Tile detects extraneous windows that are not part of the saved preset. You are presented with clear choices:

```
┌─────────────────────────────────────────────────────────────┐
│ ⚠️ Existing Windows on Workspace 2                          │
│ Workspace has 2 open window(s) not in this preset:         │
│ [Thunar (Downloads)]  [Calculator]                         │
│                                                             │
│ How would you like to handle them before restoring?        │
│ [➜ Move to WS 3]      [✕ Close]                             │
│ [◻ Keep (Float)]      [Cancel]                              │
└─────────────────────────────────────────────────────────────┘
```

1. **➜ Move to Next Free Workspace**:
   - Moves the conflicting windows to the next available empty workspace.
   - Triggers a desktop notification confirming which windows were moved.
   - Restores the saved App Preset cleanly without overlapping windows.
2. **✕ Close**:
   - Switches to the target workspace and waits for conflicting windows to close before restoring. If an app stays open, check that workspace for a save or close-confirmation dialog and retry.
   - Returns to your original workspace afterward. Missing normal Chrome windows are requested as separate new windows, including presets containing more than one Chrome window.
3. **◻ Keep (Float)**:
   - Floats the conflicting windows in place so they remain visible and accessible without breaking the restored layout's tiling tree.
4. **Cancel**:
   - Cancels restoration and leaves all windows untouched.

> **Tip (One-Click Restores)**: In the plugin settings, enable **Auto-move on restore** to automatically shift conflicting windows to the next free workspace without asking every time.

---

## 6. Right-Click Help & Handling Hints

Every button and control in Simple Tile supports contextual right-click assistance:

- **Right-Click Any Control**: Workspace cards, tab buttons, window limit caps, layout presets, save/restore buttons, and options display a guidance card explaining what the control does, when to use it, and helpful workflow tips.
- **Dismissing Hints**: Click the `✕` button on the hint card to dismiss it.
- **Disabling Hints**: If you prefer quiet operation, uncheck **Right-click help hints** in the plugin options.

---

## 7. Bar Widget & Shortcuts

- **Left-Click Bar Icon**: Opens or closes the Simple Tile settings panel.
- **Right-Click Bar Icon**: Instantly pauses or resumes automatic tiling without opening the panel.
- **Escape**: Closes the popup panel.

## Restore limits

Restoration supports ungrouped, non-fullscreen rectangular tiling arrangements.
It does not restore documents, terminal commands, or browser tabs. Monitor
geometry and gaps can affect pixel sizes. Apps that cannot open another window
may time out; the popup reports failures so you can retry.
