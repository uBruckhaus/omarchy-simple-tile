import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "native/Commons"
import qs.Commons as Theme
import "native/Ui" as Ui
import qs.Ui as ShellUi
import "LayoutState.js" as LayoutState

ShellUi.BarWidget {
    id: root
    moduleName: "ubruckhaus.simple-tile"
    readonly property bool tilingActive: setting("active", true) === true
    readonly property int cap: Math.max(1, Math.min(4, Number(setting("maxWindows", 2)) || 2))
    readonly property var workspaceCaps: setting("workspaceCaps", {}) || ({})
    readonly property var workspaceModes: setting("workspaceModes", {}) || ({})
    readonly property var workspaceLayouts: setting("workspaceLayouts", {}) || ({})
    readonly property var workspaceAutoPresets: setting("workspaceAutoPresets", {}) || ({})
    readonly property var defaultAutoPresets: setting("defaultAutoPresets", {}) || ({ "2": "side-by-side", "3": "master-left", "4": "grid" })
    readonly property int currentWsId: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0) ? Hyprland.focusedWorkspace.id : 1
    readonly property bool currentWsHasDefinedPreset: {
        if (!root.currentWsId || root.currentWsId <= 0) return false
        if (root.isWorkspaceManual(root.currentWsId)) return false
        if (root.isWorkspaceNative(root.currentWsId)) return false
        var p = root.autoPresetForWorkspace(root.currentWsId)
        return Boolean(p && p !== "none")
    }
    readonly property bool hasAnyAppPreset: {
        if (!root.workspaceLayouts) return false
        for (var k in root.workspaceLayouts) {
            var l = root.workspaceLayouts[k]
            if (l && ((l.apps && l.apps.length > 0) || (l.windows && l.windows.length > 0))) {
                return true
            }
        }
        return false
    }
    // 4 Modes:
    // 1: Disabled
    // 2: Enabled, no preset or app preset defined
    // 3: Enabled with defined presets
    // 4: Enabled and at least one app preset is defined (with green indicator)
    readonly property int currentBarIconMode: {
        if (!root.tilingActive) return 1
        if (root.hasAnyAppPreset) return 4
        if (root.currentWsHasDefinedPreset) return 3
        return 2
    }
    property int selectedWorkspace: 0
    property bool opened: false
    property string lastMessage: "New windows move on overflow in Presets. App Presets preserve custom layouts."
    property bool failed: false
    property bool autostartFinished: false
    property int autostartAttempts: 0
    property int workspacePage: 0
    readonly property var visibleWorkspaces: workspacePage === 1 ? [5, 6, 7, 8] : [1, 2, 3, 4]
    property var pending: []
    property var failedAppNames: ({})
    property var failedAppDetails: ({})
    property string activeWorkspaceTab: "presets"
    width: implicitWidth
    height: implicitHeight
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property bool rightClickHintsEnabled: setting("rightClickHints", true) !== false
    readonly property bool autoMoveOnRestore: setting("autoMoveOnRestore", false) === true
    property var restoreConflict: null
    property string activeHintTitle: ""
    property string activeHintBody: ""
    property string activeHintTip: ""
    property bool showManualView: false
    onShowManualViewChanged: panelScroll.contentY = 0

    Component.onCompleted: {
        Qt.callLater(function() {
            if (!root.tilingActive) {
                root.updateSetting("active", true)
            }
        })
    }

    onOpenedChanged: {
        if (opened) {
            restoreConflict = null
            selectedWorkspace = root.currentWsId > 0 ? root.currentWsId : 0
            if (root.currentWsId >= 5 && root.currentWsId <= 8) {
                workspacePage = 1
            } else if (root.currentWsId >= 1 && root.currentWsId <= 4) {
                workspacePage = 0
            }
            if (selectedWorkspace > 0) {
                activeWorkspaceTab = root.isWorkspaceManual(selectedWorkspace) ? "manual" : "presets"
            }
        }
    }

    onSelectedWorkspaceChanged: {
        restoreConflict = null
        if (selectedWorkspace > 0) {
            activeWorkspaceTab = root.isWorkspaceManual(selectedWorkspace) ? "manual" : "presets"
        }
    }

    onActiveWorkspaceTabChanged: {
        restoreConflict = null
    }

    function showHint(title, body, tip) {
        if (!rightClickHintsEnabled) return
        activeHintTitle = title || ""
        activeHintBody = body || ""
        activeHintTip = tip || ""
    }

    function clearHint() {
        activeHintTitle = ""
        activeHintBody = ""
        activeHintTip = ""
    }

    function helperScriptPath() {
        return decodeURIComponent(Qt.resolvedUrl("simple_tile.py").toString().replace(/^file:\/\//, ""))
    }

    function hasCustomCap(wsId) {
        if (!wsId || wsId <= 0 || !workspaceCaps) return false
        var val = workspaceCaps[String(wsId)]
        return typeof val === "number" && val >= 1 && val <= 4
    }

    function capForWorkspace(wsId) {
        if (hasCustomCap(wsId)) {
            return Number(workspaceCaps[String(wsId)])
        }
        return root.cap
    }

    function effectiveCapFor(wsId) {
        if (wsId === 0) return root.cap
        if (hasCustomCap(wsId)) {
            return Number(workspaceCaps[String(wsId)])
        }
        if (isWorkspaceManual(wsId)) {
            var wins = savedWindowsFor(wsId)
            if (wins && wins.length >= 1 && wins.length <= 4) {
                return wins.length
            }
        }
        return root.cap
    }

    function hasCustomPreset(wsId) {
        if (!wsId || wsId <= 0 || !workspaceAutoPresets) return false
        if (isWorkspaceManual(wsId)) return false
        return workspaceAutoPresets[String(wsId)] !== undefined
    }

    function defaultAutoPresetFor(capVal) {
        if (defaultAutoPresets && defaultAutoPresets[String(capVal)]) {
            return defaultAutoPresets[String(capVal)]
        }
        if (capVal === 2) return "side-by-side"
        if (capVal === 3) return "master-left"
        if (capVal === 4) return "grid"
        return "side-by-side"
    }

    function autoPresetForWorkspace(wsId) {
        if (isWorkspaceManual(wsId)) return ""
        if (wsId > 0 && workspaceAutoPresets && workspaceAutoPresets[String(wsId)]) {
            return workspaceAutoPresets[String(wsId)]
        }
        var capVal = effectiveCapFor(wsId)
        return defaultAutoPresetFor(capVal)
    }

    function isWorkspaceNative(wsId) {
        return wsId > 0 && autoPresetForWorkspace(wsId) === "none"
    }

    function selectedWindowCap(wsId) {
        return isWorkspaceNative(wsId) ? 0 : effectiveCapFor(wsId)
    }

    function autoPresetLabel(preset) {
        if (preset === "side-by-side") return "Side-by-Side"
        if (preset === "stacked") return "Stacked"
        if (preset === "master-left") return "Master Left"
        if (preset === "master-right") return "Master Right"
        if (preset === "columns") return "Columns"
        if (preset === "grid") return "2×2 Grid"
        if (preset === "none") return "None (Native)"
        return preset || "Default"
    }

    function autoPresetSymbol(preset) {
        if (preset === "side-by-side") return "⬌"
        if (preset === "stacked") return "⬍"
        if (preset === "master-left") return "◨"
        if (preset === "master-right") return "◧"
        if (preset === "columns") return "|||"
        if (preset === "grid") return "▦"
        return ""
    }

    function setWorkspaceAutoPreset(wsId, preset) {
        if (wsId <= 0) return
        var entry = Object.assign({}, settings, {id: moduleName})
        var current = Object.assign({}, workspaceAutoPresets)
        current[String(wsId)] = preset
        entry["workspaceAutoPresets"] = current

        var wasManual = isWorkspaceManual(wsId)
        if (wasManual) {
            var modes = Object.assign({}, workspaceModes)
            modes[String(wsId)] = "auto"
            entry["workspaceModes"] = modes
            if (!hasCustomCap(wsId)) {
                var currentCaps = Object.assign({}, workspaceCaps)
                currentCaps[String(wsId)] = effectiveCapFor(wsId)
                entry["workspaceCaps"] = currentCaps
            }
        }

        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
        } else {
            failed = true
            lastMessage = "Could not save settings. Try reopening the plugin."
            return
        }

        if (preset === "none") {
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--remove-preset", String(wsId)]
            lastMessage = "Workspace " + wsId + ": Native tiling, no window limit or automatic overflow"
        } else {
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), preset]
            lastMessage = "Set Workspace " + wsId + " to " + autoPresetLabel(preset) + " layout"
        }
        applyPresetWorker.running = true
    }

    function removeWorkspaceAutoPreset(wsId) {
        if (!wsId || wsId <= 0) return
        var entry = Object.assign({}, settings, {id: moduleName})
        var current = Object.assign({}, workspaceAutoPresets)
        delete current[String(wsId)]
        entry["workspaceAutoPresets"] = current

        var wasManual = isWorkspaceManual(wsId)
        if (wasManual) {
            var modes = Object.assign({}, workspaceModes)
            modes[String(wsId)] = "auto"
            entry["workspaceModes"] = modes
            if (!hasCustomCap(wsId)) {
                var currentCaps = Object.assign({}, workspaceCaps)
                currentCaps[String(wsId)] = effectiveCapFor(wsId)
                entry["workspaceCaps"] = currentCaps
            }
        }

        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
        } else {
            failed = true
            lastMessage = "Could not save settings. Try reopening the plugin."
            return
        }

        var defaultPreset = defaultAutoPresetFor(effectiveCapFor(wsId))
        applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), defaultPreset]
        applyPresetWorker.running = true
        lastMessage = "Reset Workspace " + wsId + " to default layout (" + autoPresetLabel(defaultPreset) + ")"
    }

    function toggleWorkspaceAutoPreset(wsId, preset) {
        if (wsId <= 0) return
        if (!isWorkspaceManual(wsId) && hasCustomPreset(wsId) && workspaceAutoPresets[String(wsId)] === preset) {
            removeWorkspaceAutoPreset(wsId)
        } else {
            setWorkspaceAutoPreset(wsId, preset)
        }
    }

    function setDefaultAutoPreset(capVal, preset) {
        var current = Object.assign({}, defaultAutoPresets)
        current[String(capVal)] = preset
        updateSetting("defaultAutoPresets", current)
        lastMessage = "Default for " + capVal + " windows: " + autoPresetLabel(preset)
    }

    function removeSavedApp(wsId, index) {
        if (!wsId || wsId <= 0 || !workspaceLayouts) return
        var layouts = Object.assign({}, workspaceLayouts)
        var layout = Object.assign({}, layouts[String(wsId)] || {})
        var removed = (layout.apps || [])[index]
        var updated = LayoutState.removeApp(layout, index)
        if (!updated) return
        layouts[String(wsId)] = updated
        var entry = Object.assign({}, settings, {id: moduleName})
        entry["workspaceLayouts"] = layouts
        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
            lastMessage = "Removed " + (removed.name || "app") + " from the saved layout."
        } else {
            failed = true
            lastMessage = "Could not save the removal. Try again."
        }
    }


    function recordFailedApps(wsId, failedList) {
        var names = failedList.map(function(f) { return (f.name || f.class || "").toLowerCase() })
        var map = Object.assign({}, failedAppNames)
        map[String(wsId)] = names
        failedAppNames = map
        var details = Object.assign({}, failedAppDetails)
        details[String(wsId)] = failedList.slice()
        failedAppDetails = details
    }

    function restoreFailureText(wsId) {
        var failures = failedAppDetails[String(wsId)] || []
        var reasons = {
            window_timeout: "No matching window appeared before the restore timed out.",
            close_timeout: "The window did not close. Check Workspace " + wsId + " for a save or close-confirmation dialog, then retry Restore.",
            launch_failed: "The app could not be launched.",
            command_not_found: "The saved launch command could not be found.",
            desktop_file_not_found: "The saved app launcher could not be found.",
            workspace_move_failed: "The window could not be moved to this workspace.",
            app_launching_disabled: "Launching missing apps is disabled for this preset."
        }
        return failures.map(function(f) {
            return (f.name || f.class || "App") + ": " + (reasons[f.reason] || f.reason || "Restore failed without a reason.")
        }).join("\n")
    }

    function isAppFailed(wsId, app) {
        if (!failedAppNames || !failedAppNames[String(wsId)]) return false
        var name = (app.name || app.class || "").toLowerCase()
        var list = failedAppNames[String(wsId)]
        for (var i = 0; i < list.length; i++) {
            if (list[i] === name) return true
        }
        return false
    }

    function isWorkspaceManual(wsId) {
        if (!wsId || wsId <= 0) return false
        var mode = workspaceModes ? workspaceModes[String(wsId)] : undefined
        if (mode === "manual") return true
        if (mode === "auto") return false
        var layout = workspaceLayouts ? workspaceLayouts[String(wsId)] : null
        return (layout && layout.mode === "manual") === true
    }

    function layoutForWorkspace(wsId) {
        if (!wsId || wsId <= 0 || !workspaceLayouts) return null
        return workspaceLayouts[String(wsId)] || null
    }

    function hasSavedLayout(wsId) {
        var layout = layoutForWorkspace(wsId)
        return layout && ((layout.windows && layout.windows.length > 0) || (layout.apps && layout.apps.length > 0))
    }

    function savedAppsFor(wsId) {
        var layout = layoutForWorkspace(wsId)
        if (!layout || layout.saveApps === false || !layout.apps) return []
        return layout.apps
    }

    function savedWindowsFor(wsId) {
        var layout = layoutForWorkspace(wsId)
        if (!layout || !layout.windows) return []
        return layout.windows
    }

    function calculateWindowBounds(windows) {
        if (!windows || windows.length === 0) return { minX: 0, minY: 0, w: 1920, h: 1080 }
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i]
            var at = w.at || [0, 0]
            var sz = w.size || [800, 600]
            if (at[0] < minX) minX = at[0]
            if (at[1] < minY) minY = at[1]
            if (at[0] + sz[0] > maxX) maxX = at[0] + sz[0]
            if (at[1] + sz[1] > maxY) maxY = at[1] + sz[1]
        }
        return {
            minX: minX,
            minY: minY,
            w: Math.max(1, maxX - minX),
            h: Math.max(1, maxY - minY)
        }
    }

    function workspaceSaveApps(wsId) {
        var layout = layoutForWorkspace(wsId)
        return layout ? (layout.saveApps !== false) : true
    }

    function workspaceAutostart(wsId) {
        var layout = layoutForWorkspace(wsId)
        return layout ? (layout.autostart === true) : false
    }

    function savedLayoutSummary(wsId) {
        var layout = layoutForWorkspace(wsId)
        if (!layout) return "None"
        var winCount = layout.count || (layout.windows ? layout.windows.length : 0)
        return winCount + (winCount === 1 ? " window" : " windows")
    }

    function resolveIcon(iconName) {
        if (!iconName || typeof iconName !== "string") {
            return Quickshell.iconPath("application-x-executable", true)
        }
        if (iconName.indexOf("file://") === 0 || iconName.indexOf("image://") === 0) {
            return iconName
        }
        if (iconName.charAt(0) === "/") {
            return "file://" + iconName
        }
        if (bar && bar.shell && bar.shell.appLibrary) {
            var src = bar.shell.appLibrary.iconSource(iconName)
            if (src && src.length > 0) return src
        }
        var themed = Quickshell.iconPath(iconName, true)
        if (themed && themed.length > 0) return themed
        return Quickshell.iconPath("application-x-executable", true)
    }

    readonly property int activeWsCap: capForWorkspace(currentWsId)
    readonly property bool activeWsCustom: hasCustomCap(currentWsId)

    readonly property var workspaceList: {
        var list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            var vals = Hyprland.workspaces.values
            for (var i = 0; i < vals.length; i++) {
                var wid = vals[i].id
                if (wid > 0 && list.indexOf(wid) === -1) list.push(wid)
            }
        }
        if (workspaceCaps) {
            for (var k in workspaceCaps) {
                var kwid = parseInt(k, 10)
                if (kwid > 0 && list.indexOf(kwid) === -1) list.push(kwid)
            }
        }
        if (workspaceLayouts) {
            for (var lk in workspaceLayouts) {
                var lwid = parseInt(lk, 10)
                if (lwid > 0 && list.indexOf(lwid) === -1) list.push(lwid)
            }
        }
        list.sort(function(a, b) { return a - b })
        return list
    }

    function setWorkspaceCap(wsId, newCap) {
        if (!wsId || wsId <= 0) return
        var entry = Object.assign({}, settings, {id: moduleName})
        var current = Object.assign({}, workspaceCaps)
        current[String(wsId)] = newCap
        entry["workspaceCaps"] = current

        var wasNative = isWorkspaceNative(wsId)
        if (wasNative) {
            var presets = Object.assign({}, workspaceAutoPresets)
            presets[String(wsId)] = defaultAutoPresetFor(newCap)
            entry["workspaceAutoPresets"] = presets
        }
        var wasManual = isWorkspaceManual(wsId)
        if (wasManual) {
            var modes = Object.assign({}, workspaceModes)
            modes[String(wsId)] = "auto"
            entry["workspaceModes"] = modes
        }

        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
            lastMessage = "Set Workspace " + wsId + " limit to " + newCap + " windows"
        } else {
            failed = true
            lastMessage = "Could not save settings. Try reopening the plugin."
            return
        }

        if (wasManual || wasNative) {
            var activePreset = autoPresetForWorkspace(wsId) || defaultAutoPresetFor(newCap)
            if (activePreset && activePreset !== "none" && newCap > 1) {
                applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), activePreset]
                applyPresetWorker.running = true
            }
        }
    }

    function resetWorkspaceCap(wsId) {
        if (!wsId || wsId <= 0) return
        var entry = Object.assign({}, settings, {id: moduleName})
        var current = Object.assign({}, workspaceCaps)
        delete current[String(wsId)]
        entry["workspaceCaps"] = current

        var wasManual = isWorkspaceManual(wsId)
        if (wasManual) {
            var modes = Object.assign({}, workspaceModes)
            modes[String(wsId)] = "auto"
            entry["workspaceModes"] = modes
        }

        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
            lastMessage = "Reset Workspace " + wsId + " limit to default (" + root.cap + " windows)"
        } else {
            failed = true
            lastMessage = "Could not save settings. Try reopening the plugin."
            return
        }

        if (wasManual) {
            var activePreset = autoPresetForWorkspace(wsId) || defaultAutoPresetFor(root.cap)
            if (activePreset && activePreset !== "none" && root.cap > 1) {
                applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), activePreset]
                applyPresetWorker.running = true
            }
        }
    }

    function setWorkspaceMode(wsId, mode) {
        if (!wsId || wsId <= 0 || (mode !== "auto" && mode !== "manual")) return
        var modes = Object.assign({}, workspaceModes)
        modes[String(wsId)] = mode
        updateSetting("workspaceModes", modes)
        if (failed) return
        activeWorkspaceTab = mode === "manual" ? "manual" : "presets"
        if (mode === "manual") {
            lastMessage = "Workspace " + wsId + ": open, close and arrange windows freely. Save to update the App Preset."
        } else {
            var preset = autoPresetForWorkspace(wsId)
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), preset]
            applyPresetWorker.running = true
            lastMessage = preset === "none"
                ? "Workspace " + wsId + ": Native tiling, no window limit or automatic overflow"
                : "Workspace " + wsId + ": resumed " + autoPresetLabel(preset) + " layout and automatic overflow"
        }
    }

    function toggleWorkspaceSaveApps(wsId) {
        var layouts = Object.assign({}, workspaceLayouts)
        var layout = Object.assign({}, layouts[String(wsId)] || {})
        layout.saveApps = !(layout.saveApps !== false)
        layouts[String(wsId)] = layout
        updateSetting("workspaceLayouts", layouts)
    }

    function toggleWorkspaceAutostart(wsId) {
        var layouts = Object.assign({}, workspaceLayouts)
        var layout = Object.assign({}, layouts[String(wsId)] || {})
        layout.autostart = !layout.autostart
        layouts[String(wsId)] = layout
        updateSetting("workspaceLayouts", layouts)
    }

    function clearWorkspaceLayout(wsId) {
        var layouts = Object.assign({}, workspaceLayouts)
        delete layouts[String(wsId)]
        var modes = Object.assign({}, workspaceModes)
        delete modes[String(wsId)]
        var entry = Object.assign({}, settings, {id: moduleName})
        entry["workspaceLayouts"] = layouts
        entry["workspaceModes"] = modes
        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
            lastMessage = "Cleared App Preset for Workspace " + wsId
            var defaultPreset = autoPresetForWorkspace(wsId) || defaultAutoPresetFor(effectiveCapFor(wsId))
            if (defaultPreset && defaultPreset !== "none") {
                applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), defaultPreset]
                applyPresetWorker.running = true
            }
        }
    }

    function captureWorkspaceLayout(wsId) {
        if (!wsId || wsId <= 0) return
        captureWorker.targetWs = wsId
        captureWorker.command = ["python3", root.helperScriptPath(), "--capture-workspace", String(wsId)]
        captureWorker.running = true
    }

    function onWorkspaceCaptured(wsId, res) {
        var layouts = Object.assign({}, workspaceLayouts)
        var existing = layouts[String(wsId)] || {}
        var saveApps = existing.saveApps !== undefined ? existing.saveApps : true
        var autostart = existing.autostart !== undefined ? existing.autostart : false
        layouts[String(wsId)] = {
            mode: "manual",
            saveApps: saveApps,
            autostart: autostart,
            apps: res.apps || [],
            windows: res.windows || [],
            count: res.count || 0,
            savedAt: Date.now()
        }
        var modes = Object.assign({}, workspaceModes)
        modes[String(wsId)] = "manual"
        var entry = Object.assign({}, settings, {id: moduleName})
        entry["workspaceLayouts"] = layouts
        entry["workspaceModes"] = modes
        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
            lastMessage = "Saved App Preset for Workspace " + wsId + " (" + (res.count || 0) + " windows)"
            activeWorkspaceTab = "manual"
        }
    }

    function restoreWorkspaceApps(wsId, conflictAction) {
        if (!wsId || wsId <= 0 || actionWorker.running || autostartWorker.running) return
        var action = conflictAction || (root.autoMoveOnRestore ? "move" : "ask")
        actionWorker.targetWs = wsId
        actionWorker.command = ["python3", root.helperScriptPath(), "--restore-workspace", String(wsId), "--conflict-action", action]
        actionWorker.running = true
    }

    function open() {
        selectedWorkspace = root.currentWsId > 0 ? root.currentWsId : 0
        opened = true
    }
    function close() { opened = false }
    function closeForPopoutSwitch() { close() }
    function togglePanel() {
        if (opened) close()
        else open()
    }
    function updateSetting(key, value) {
        if (settings[key] === value) return
        var entry = Object.assign({}, settings, {id: moduleName})
        entry[key] = value
        if (bar && bar.shell && bar.shell.updateEntryInline(moduleName, entry)) {
            settings = entry
            failed = false
        } else {
            failed = true
            lastMessage = "Could not save settings. Try reopening the plugin."
        }
    }
    function nextWindow() {
        if (worker.running || pending.length === 0) return
        if (!tilingActive) { pending = []; return }
        var queue = pending.slice()
        var address = queue.shift()
        pending = queue
        worker.command = ["python3", root.helperScriptPath(), "--window", address]
        worker.running = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "openwindow" || !root.tilingActive) return
            var address = event.data.split(",")[0]
            if (!/^(0x)?[0-9a-fA-F]+$/.test(address)) return
            root.pending = root.pending.concat([address])
            settle.restart()
        }
    }
    Timer { id: settle; interval: 150; onTriggered: root.nextWindow() }

    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    root.failed = result.status === "error"
                    if (root.failed) root.lastMessage = "Could not move the window. Check the shell log."
                    else if (result.status === "moved") root.lastMessage = "Last move: workspace " + result.source + " → " + result.target
                    else if (result.status === "manual") root.lastMessage = "Workspace " + result.workspace + " is using App Presets."
                    if (root.failed) console.warn("Simple Tile:", result.message)
                } catch (error) {
                    root.failed = true
                    root.lastMessage = "The window helper returned an invalid response."
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                root.failed = true
                root.lastMessage = "Window helper failed. Check the shell log."
            }
            settle.restart()
        }
    }

    Process {
        id: captureWorker
        property int targetWs: 0
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var res = JSON.parse(text)
                    if (res.status === "ok") {
                        root.onWorkspaceCaptured(captureWorker.targetWs, res)
                    } else {
                        root.failed = true
                        root.lastMessage = "Capture failed: " + (res.message || "Unknown error")
                    }
                } catch (e) {
                    root.failed = true
                    root.lastMessage = "The capture helper returned an invalid response."
                }
            }
        }
    }

    Process {
        id: actionWorker
        property int targetWs: 0
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var res = JSON.parse(text)
                    if (res.status === "conflict") {
                        root.failed = false
                        root.restoreConflict = res
                        root.lastMessage = "Workspace " + res.workspace + " has " + res.conflict_count + " open window(s) not in this preset."
                    } else if (res.failed && res.failed.length > 0) {
                        root.restoreConflict = null
                        root.failed = true
                        root.recordFailedApps(res.workspace || actionWorker.targetWs, res.failed)
                        var failedNames = root.restoreFailureText(res.workspace || actionWorker.targetWs)
                        if (res.launched && res.launched.length > 0) {
                            root.lastMessage = "Launched: " + res.launched.join(", ") + " · Could not restore: " + failedNames
                        } else {
                            root.lastMessage = "Could not restore: " + failedNames
                        }
                    } else if (res.status === "ok") {
                        root.restoreConflict = null
                        root.failed = false
                        root.recordFailedApps(res.workspace || actionWorker.targetWs, [])
                        if (res.launched && res.launched.length > 0) {
                            root.lastMessage = "Launched: " + res.launched.join(", ")
                        } else if (res.already_running && res.already_running.length > 0) {
                            root.lastMessage = (res.geometry_restored ? "Restored layout: " : "Already open: ") + res.already_running.join(", ")
                        } else {
                            root.lastMessage = "Action completed."
                        }
                    } else if (res.message) {
                        root.failed = res.status === "error"
                        root.lastMessage = "Workspace " + actionWorker.targetWs + ": " + res.message
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: applyPresetWorker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var res = JSON.parse(text)
                    if (res.status === "ok") {
                        if (res.preset === "none") {
                            root.lastMessage = "Preset removed (Native layout) on Workspace " + res.workspace
                        } else {
                            root.lastMessage = "Applied " + root.autoPresetLabel(res.preset) + " to Workspace " + res.workspace
                        }
                    } else if (res.message) {
                        root.lastMessage = res.message
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: autostartWorker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var res = JSON.parse(text)
                    if (res.status === "ok" || res.status === "partial" || res.status === "already_started")
                        root.autostartFinished = true
                    if (res.failed_count > 0) {
                        root.failed = true
                        root.lastMessage = "Some saved windows could not be restored. Open their workspace and try Restore again."
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        id: autostartTimer
        interval: 2000
        running: !root.autostartFinished && Object.keys(root.workspaceLayouts).some(function(k) {
            return root.workspaceLayouts[k] && root.workspaceLayouts[k].autostart === true
        })
        repeat: true
        onTriggered: {
            if (autostartWorker.running) return
            if (++root.autostartAttempts > 15) {
                root.autostartFinished = true
                root.failed = true
                root.lastMessage = "Autostart could not connect. Use Restore to retry."
                return
            }
            for (var k in root.workspaceLayouts) {
                if (root.workspaceLayouts[k] && root.workspaceLayouts[k].autostart) {
                    autostartWorker.command = ["python3", root.helperScriptPath(), "--autostart"]
                    autostartWorker.running = true
                    return
                }
            }
        }
    }

    Component {
        id: tileIconComponent
        Item {
            anchors.fill: parent

            readonly property string currentPreset: root.autoPresetForWorkspace(root.currentWsId) || root.defaultAutoPresetFor(root.effectiveCapFor(root.currentWsId))
            readonly property bool isManual: root.isWorkspaceManual(root.currentWsId)
            readonly property bool isNative: root.isWorkspaceNative(root.currentWsId)
            readonly property color tileColor: root.failed ? Color.urgent : (button.active ? Color.accent : (button.foreground || Color.foreground))
            readonly property int mode: root.currentBarIconMode

            Item {
                width: 14
                height: 12
                anchors.centerIn: parent

                // ==========================================
                // 1. OUTLINE TILES (Mode 1: Disabled, Mode 2: No preset defined, or Native)
                // ==========================================
                Item {
                    anchors.fill: parent
                    visible: mode === 1 || mode === 2 || (!isManual && isNative)

                    Rectangle {
                        x: 0; y: 0; width: 6; height: 12; radius: 1.5
                        color: "transparent"
                        border.width: 1
                        border.color: tileColor
                        opacity: mode === 1 ? 0.35 : 0.85
                    }
                    Rectangle {
                        x: 8; y: 0; width: 6; height: 12; radius: 1.5
                        color: "transparent"
                        border.width: 1
                        border.color: tileColor
                        opacity: mode === 1 ? 0.20 : 0.50
                    }
                }

                // ==========================================
                // 2. FILLED PRESET TILES (Mode 3: Defined presets, Mode 4: App presets)
                // ==========================================
                Item {
                    anchors.fill: parent
                    visible: (mode === 3 || mode === 4) && !isNative

                    // A. Side-by-Side (2 windows: left master, right secondary)
                    Item {
                        anchors.fill: parent
                        visible: (!isManual && (currentPreset === "side-by-side" || !currentPreset)) || (isManual && (!currentPreset || currentPreset === "side-by-side"))
                        Rectangle {
                            x: 0; y: 0; width: 6; height: 12; radius: 1.5
                            color: tileColor
                            opacity: 0.95
                        }
                        Rectangle {
                            x: 8; y: 0; width: 6; height: 12; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                    }

                    // B. Stacked (2 windows: top & bottom)
                    Item {
                        anchors.fill: parent
                        visible: !isManual && currentPreset === "stacked"
                        Rectangle {
                            x: 0; y: 0; width: 14; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.95
                        }
                        Rectangle {
                            x: 0; y: 7; width: 14; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                    }

                    // C. Master Left (3 or 4 windows: master left, 2 stacked right)
                    Item {
                        anchors.fill: parent
                        visible: !isManual && currentPreset === "master-left"
                        Rectangle {
                            x: 0; y: 0; width: 8; height: 12; radius: 1.5
                            color: tileColor
                            opacity: 0.95
                        }
                        Rectangle {
                            x: 10; y: 0; width: 4; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                        Rectangle {
                            x: 10; y: 7; width: 4; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                    }

                    // D. Master Right (3 or 4 windows: 2 stacked left, master right)
                    Item {
                        anchors.fill: parent
                        visible: !isManual && currentPreset === "master-right"
                        Rectangle {
                            x: 0; y: 0; width: 4; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                        Rectangle {
                            x: 0; y: 7; width: 4; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                        Rectangle {
                            x: 6; y: 0; width: 8; height: 12; radius: 1.5
                            color: tileColor
                            opacity: 0.95
                        }
                    }

                    // E. Grid (4 windows: 2x2 quadrants)
                    Item {
                        anchors.fill: parent
                        visible: !isManual && currentPreset === "grid"
                        Rectangle {
                            x: 0; y: 0; width: 6; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.95
                        }
                        Rectangle {
                            x: 8; y: 0; width: 6; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                        Rectangle {
                            x: 0; y: 7; width: 6; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                        Rectangle {
                            x: 8; y: 7; width: 6; height: 5; radius: 1.5
                            color: tileColor
                            opacity: 0.55
                        }
                    }

                    // F. Columns (3 or 4 windows: vertical strips)
                    Item {
                        anchors.fill: parent
                        visible: !isManual && currentPreset === "columns"
                        Rectangle {
                            x: 0; y: 0; width: 3; height: 12; radius: 1
                            color: tileColor
                            opacity: 0.95
                        }
                        Rectangle {
                            x: 5; y: 0; width: 4; height: 12; radius: 1
                            color: tileColor
                            opacity: 0.55
                        }
                        Rectangle {
                            x: 11; y: 0; width: 3; height: 12; radius: 1
                            color: tileColor
                            opacity: 0.55
                        }
                    }
                }

                // ==========================================
                // MODE 1: PAUSE BARS (When disabled)
                // ==========================================
                Item {
                    visible: mode === 1
                    anchors.centerIn: parent
                    width: 5; height: 6
                    Rectangle { x: 0; y: 0; width: 1.5; height: 6; radius: 0.5; color: Color.urgent }
                    Rectangle { x: 3.5; y: 0; width: 1.5; height: 6; radius: 0.5; color: Color.urgent }
                }

                // ==========================================
                // MODE 4: GREEN INDICATOR (At least one App Preset is defined)
                // ==========================================
                Rectangle {
                    visible: mode === 4 && root.tilingActive
                    x: 10; y: -1; width: 5; height: 5; radius: 2.5
                    color: "#22c55e"
                    border.width: 1
                    border.color: Color.background

                    // Subtle halo when the active workspace is in App Presets mode
                    Rectangle {
                        visible: root.isWorkspaceManual(root.currentWsId)
                        anchors.centerIn: parent
                        width: parent.width + 2
                        height: parent.height + 2
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: "#86efac"
                        opacity: 0.75
                    }
                }

                // Failure badge (exclamation point)
                Rectangle {
                    visible: root.failed
                    x: 9; y: -1; width: 6; height: 6; radius: 3
                    color: Color.urgent
                    Text {
                        anchors.centerIn: parent
                        text: "!"
                        color: "#ffffff"
                        font.pixelSize: 5
                        font.bold: true
                    }
                }
            }
        }
    }

    ShellUi.BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: tileIconComponent
        active: root.failed || root.opened
        dimmed: !root.tilingActive
        tooltipText: {
            if (root.currentBarIconMode === 1) {
                return "Simple Tile · 1. Disabled (Paused)\nClick for settings · Right-click to resume"
            }
            if (root.currentBarIconMode === 2) {
                return "Simple Tile · 2. Enabled (No preset or app preset defined)\nWorkspace " + root.currentWsId + ": Native tiling\nClick for settings · Right-click to pause"
            }
            if (root.currentBarIconMode === 3) {
                return "Simple Tile · 3. Enabled with defined presets\nWorkspace " + root.currentWsId + ": " + root.autoPresetLabel(root.autoPresetForWorkspace(root.currentWsId)) + " (" + root.capForWorkspace(root.currentWsId) + " windows limit)\nClick for settings · Right-click to pause"
            }
            var appCount = root.savedAppsFor(root.currentWsId).length
            var status = root.isWorkspaceManual(root.currentWsId)
                ? ("Workspace " + root.currentWsId + ": App Presets active" + (appCount > 0 ? " (" + appCount + " apps saved)" : ""))
                : ("Workspace " + root.currentWsId + ": Preset " + root.autoPresetLabel(root.autoPresetForWorkspace(root.currentWsId)) + " · App Preset defined")
            return "Simple Tile · 4. Enabled with App Preset (Green indicator)\n" + status + "\nClick for settings · Right-click to pause"
        }
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.RightButton) root.updateSetting("active", !root.tilingActive)
            else root.togglePanel()
        }
    }

    Ui.KeyboardPanel {
        id: popup
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        focusTarget: content
        contentWidth: popup.fittedContentWidth(Style.space(420))
        contentHeight: popup.fittedContentHeight(content.implicitHeight)

        Flickable {
            id: panelScroll
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
        Column {
            id: content
            width: parent.width
            spacing: Style.space(12)
            Keys.onEscapePressed: root.close()

            Item {
                width: parent.width
                height: Style.space(28)

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Simple Tile"
                    color: Theme.Color.accent
                    font.family: Theme.Style.font.family
                    font.pixelSize: Theme.Style.font.title
                    font.bold: true
                }

                Ui.Button {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: Style.space(24)
                    text: root.showManualView ? "✕ Close Manual" : "📖 User Manual"
                    fontSize: Style.font.caption
                    bordered: true
                    focusable: true
                    selected: root.showManualView
                    onClicked: root.showManualView = !root.showManualView
                    onRightClicked: root.showHint("User Manual", "Open the comprehensive plugin manual with full explanations of Presets, App Presets, Autostart, and Conflict handling.", "Tip: Left-click to view the manual directly in this panel.")
                    tooltipText: "Open or close the integrated Simple Tile User Manual"
                }
            }

            Text {
                width: parent.width
                text: "A little room to focus."
                color: Color.foreground
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            Ui.Toggle {
                width: parent.width
                label: root.tilingActive ? "Tiling active" : "Tiling paused"
                description: "Move new windows when full · Manual moves override"
                checked: root.tilingActive
                onClicked: root.updateSetting("active", !root.tilingActive)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: root.showHint("Tiling Active Toggle", "Temporarily pause or resume Simple Tile's automatic window movement without losing any saved presets.", "Tip: You can also right-click the bar icon anytime to toggle this.")
                }
            }

            // Contextual Hint Card
            Rectangle {
                visible: root.activeHintTitle !== "" && root.rightClickHintsEnabled
                width: parent.width
                implicitHeight: hintCol.implicitHeight + Style.space(16)
                radius: Style.space(6)
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                border.width: 1
                border.color: Color.accent

                Column {
                    id: hintCol
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    spacing: Style.space(4)

                    Row {
                        width: parent.width
                        Item {
                            width: parent.width - closeHintBtn.width
                            height: closeHintBtn.height
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(4)
                                Text {
                                    text: "💡"
                                    font.pixelSize: Style.font.bodySmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.activeHintTitle
                                    color: Color.accent
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                        Ui.Button {
                            id: closeHintBtn
                            implicitWidth: Style.space(20)
                            implicitHeight: Style.space(20)
                            text: "✕"
                            fontSize: Style.font.caption
                            bordered: false
                            onClicked: root.clearHint()
                            tooltipText: "Dismiss hint"
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.activeHintBody
                        color: Color.foreground
                        opacity: 0.9
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }

                    Text {
                        visible: root.activeHintTip !== ""
                        width: parent.width
                        text: root.activeHintTip
                        color: Color.accent
                        opacity: 0.95
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.italic: true
                        wrapMode: Text.Wrap
                    }
                }
            }

            // MAIN WORKSPACE CONTROLS VIEW (Visible when not showing User Manual)
            Column {
                id: workspaceControlsView
                visible: !root.showManualView
                width: parent.width
                spacing: Style.space(12)

                Item {
                    width: parent.width
                    height: Style.space(22)

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "WORKSPACES"
                        color: Color.foreground
                        opacity: 0.65
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)

                        Ui.Button {
                            implicitHeight: Style.space(20)
                            implicitWidth: Style.space(40)
                            text: "1 – 4"
                            selected: root.workspacePage === 0
                            bordered: true
                            focusable: true
                            onClicked: root.workspacePage = 0
                            onRightClicked: root.showHint("Workspaces 1–4", "Display the first page of workspaces (Workspaces 1 to 4). Cards show live layouts and app snapshots.", "")
                            Accessible.name: "Workspaces 1 to 4"
                        }

                        Ui.Button {
                            implicitHeight: Style.space(20)
                            implicitWidth: Style.space(40)
                            text: "5 – 8"
                            selected: root.workspacePage === 1
                            bordered: true
                            focusable: true
                            onClicked: root.workspacePage = 1
                            onRightClicked: root.showHint("Workspaces 5–8", "Display the second page of workspaces (Workspaces 5 to 8). Cards show live layouts and app snapshots.", "")
                            Accessible.name: "Workspaces 5 to 8"
                        }
                    }
                }

                Ui.Button {
                    id: allCard
                    width: parent.width
                    implicitHeight: Style.space(34)
                    selected: root.selectedWorkspace === 0
                    bordered: true
                    focusable: true
                    onClicked: root.selectedWorkspace = 0
                    onRightClicked: root.showHint("All Workspaces", "Select the global default scope. Any setting configured here applies to all workspaces that do not have custom overrides.", "Tip: Set the default limit to 2 or 3 for standard workflow.")
                    Accessible.name: "All workspaces default"
                    tooltipText: "Set the default window limit applied to all workspaces"

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    enabled: false

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "All Workspaces"
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: allCard.selected
                        opacity: allCard.selected ? 1.0 : 0.85
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Default: " + root.cap + " windows"
                        color: allCard.selected ? Color.accent : Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        opacity: allCard.selected ? 1.0 : 0.65
                    }
                }
            }
            Grid {
                width: parent.width
                columns: 4
                spacing: Style.space(6)
                Repeater {
                    model: root.visibleWorkspaces
                    Ui.Button {
                        id: wsCard
                        required property int modelData
                        width: (content.width - Style.space(18)) / 4
                        implicitHeight: Style.space(84)
                        selected: root.selectedWorkspace === modelData
                        bordered: true
                        focusable: true
                        readonly property bool isManual: root.isWorkspaceManual(wsCard.modelData)
                        readonly property var savedApps: root.savedAppsFor(wsCard.modelData)
                        readonly property var savedWindows: root.savedWindowsFor(wsCard.modelData)
                        readonly property bool hasSavedApps: savedApps && savedApps.length > 0
                        tooltipText: {
                            var base = "Workspace " + modelData + (modelData === root.currentWsId ? " (Active)" : "")
                            if (wsCard.isManual) {
                                var summary = wsCard.hasSavedApps ? (wsCard.savedApps.length + " apps saved") : "App Preset"
                                if (root.workspaceAutostart(modelData)) summary += " · Autostart on"
                                return base + "\n" + summary
                            }
                            if (root.isWorkspaceNative(modelData)) return base + "\nNative tiling · No window limit or automatic overflow"
                            var presetKey = root.autoPresetForWorkspace(modelData)
                            var presetDesc = presetKey === "none" ? "Native (no preset)" : (root.autoPresetLabel(presetKey) + (root.hasCustomPreset(modelData) ? " (custom)" : " (default)"))
                            return base + "\nLimit: " + root.capForWorkspace(modelData) + " windows · Preset: " + presetDesc
                        }
                        onClicked: root.selectedWorkspace = modelData
                        onRightClicked: root.showHint("Workspace " + wsCard.modelData + " Card", wsCard.isManual ? ("Workspace " + wsCard.modelData + " is in App Presets mode (" + root.savedLayoutSummary(wsCard.modelData) + "). Custom window geometry is preserved and overflow moves are disabled.") : root.isWorkspaceNative(wsCard.modelData) ? ("Workspace " + wsCard.modelData + " uses native tiling without a window limit or automatic overflow.") : ("Workspace " + wsCard.modelData + " is in Presets mode with a limit of " + root.capForWorkspace(wsCard.modelData) + " windows and " + root.autoPresetLabel(root.autoPresetForWorkspace(wsCard.modelData)) + " layout."), "Tip: Left-click to select and configure this workspace.")
                        Accessible.name: "Workspace " + modelData

                        Item {
                            anchors.fill: parent
                            anchors.topMargin: Style.space(3)
                            anchors.bottomMargin: Style.space(3)
                            anchors.leftMargin: Style.space(5)
                            anchors.rightMargin: Style.space(5)
                            enabled: false

                            Item {
                                id: cardHeader
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: Style.space(14)

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(3)

                                    Text {
                                        text: wsCard.modelData
                                        color: Color.foreground
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: true
                                        opacity: wsCard.selected ? 1.0 : 0.8
                                    }

                                    Rectangle {
                                        width: Style.space(5)
                                        height: Style.space(5)
                                        radius: width / 2
                                        color: Color.accent
                                        visible: wsCard.modelData === root.currentWsId
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: wsCard.isManual ? "App Preset" : (root.isWorkspaceNative(wsCard.modelData) ? "No limit" : ("Max " + root.capForWorkspace(wsCard.modelData)))
                                    color: (wsCard.isManual || root.hasCustomCap(wsCard.modelData)) ? Color.accent : Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: wsCard.isManual ? Math.max(9, Style.font.caption - 2) : Style.font.caption
                                    font.bold: wsCard.isManual || root.hasCustomCap(wsCard.modelData)
                                    opacity: (wsCard.selected || wsCard.isManual || root.hasCustomCap(wsCard.modelData)) ? 1.0 : 0.65
                                }
                            }

                            Rectangle {
                                id: cardDivider
                                anchors.top: cardHeader.bottom
                                anchors.topMargin: Style.space(2)
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: Color.foreground
                                opacity: 0.12
                            }

                            Item {
                                id: cardBody
                                anchors.top: cardDivider.bottom
                                anchors.topMargin: Style.space(3)
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Style.space(3)
                                anchors.left: parent.left
                                anchors.right: parent.right

                                // Mini Monitor Screen Container
                                Rectangle {
                                    id: miniScreen
                                    anchors.centerIn: parent
                                    width: Style.space(56)
                                    height: Style.space(36)
                                    radius: 3
                                    color: "#121217"
                                    border.width: 1
                                    border.color: wsCard.selected ? Color.accent : (wsCard.modelData === root.currentWsId ? Color.accent : "#2c2d38")
                                    clip: true

                                    // CASE 1: Manual mode with saved windows
                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        visible: wsCard.isManual && wsCard.savedWindows.length > 0

                                        Repeater {
                                            model: wsCard.savedWindows
                                            Rectangle {
                                                required property var modelData
                                                readonly property var bounds: root.calculateWindowBounds(wsCard.savedWindows)
                                                readonly property real normX: bounds.w > 0 ? (modelData.at[0] - bounds.minX) / bounds.w : 0
                                                readonly property real normY: bounds.h > 0 ? (modelData.at[1] - bounds.minY) / bounds.h : 0
                                                readonly property real normW: bounds.w > 0 ? modelData.size[0] / bounds.w : 1
                                                readonly property real normH: bounds.h > 0 ? modelData.size[1] / bounds.h : 1

                                                x: Math.round(normX * parent.width) + 1
                                                y: Math.round(normY * parent.height) + 1
                                                width: Math.max(6, Math.round(normW * parent.width) - 2)
                                                height: Math.max(6, Math.round(normH * parent.height) - 2)
                                                radius: 2
                                                color: Color.accentContainer || "#262b3d"
                                                border.width: 1
                                                border.color: Color.accent
                                                opacity: 0.9

                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    height: 2
                                                    color: Color.accent
                                                }

                                                Image {
                                                    anchors.centerIn: parent
                                                    width: Math.min(parent.width - 2, Style.space(12))
                                                    height: Math.min(parent.height - 2, Style.space(12))
                                                    sourceSize.width: Style.space(12)
                                                    sourceSize.height: Style.space(12)
                                                    source: root.resolveIcon(modelData.app ? modelData.app.icon : modelData.icon)
                                                    smooth: true
                                                    visible: width >= 6 && height >= 6
                                                }
                                            }
                                        }
                                    }

                                    // CASE 1b: Manual mode without saved windows
                                    Text {
                                        anchors.centerIn: parent
                                        visible: wsCard.isManual && wsCard.savedWindows.length === 0
                                        text: "No App Preset"
                                        color: Color.foreground
                                        opacity: 0.4
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                    }

                                    // CASE 2: Auto mode presets
                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        visible: !wsCard.isManual

                                        readonly property string preset: root.autoPresetForWorkspace(wsCard.modelData)
                                        readonly property int capVal: root.capForWorkspace(wsCard.modelData)

                                        // Preset: 1 window
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: parent.capVal === 1 && parent.preset !== "none"
                                            radius: 2
                                            color: Color.accentContainer || "#262b3d"
                                            border.width: 1
                                            border.color: Color.accent
                                            opacity: 0.85
                                            Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                        }

                                        // Preset: 2 windows - Side-by-Side
                                        Row {
                                            anchors.fill: parent
                                            spacing: 2
                                            visible: parent.capVal === 2 && parent.preset !== "stacked" && parent.preset !== "none"
                                            Rectangle {
                                                width: (parent.width - 2) / 2
                                                height: parent.height
                                                radius: 2
                                                color: Color.accentContainer || "#262b3d"
                                                border.width: 1
                                                border.color: Color.accent
                                                opacity: 0.85
                                                Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                            }
                                            Rectangle {
                                                width: (parent.width - 2) / 2
                                                height: parent.height
                                                radius: 2
                                                color: Color.accentContainer || "#262b3d"
                                                border.width: 1
                                                border.color: Color.accent
                                                opacity: 0.85
                                                Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                            }
                                        }

                                        // Preset: 2 windows - Stacked
                                        Column {
                                            anchors.fill: parent
                                            spacing: 2
                                            visible: parent.capVal === 2 && parent.preset === "stacked"
                                            Rectangle {
                                                width: parent.width
                                                height: (parent.height - 2) / 2
                                                radius: 2
                                                color: Color.accentContainer || "#262b3d"
                                                border.width: 1
                                                border.color: Color.accent
                                                opacity: 0.85
                                                Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                            }
                                            Rectangle {
                                                width: parent.width
                                                height: (parent.height - 2) / 2
                                                radius: 2
                                                color: Color.accentContainer || "#262b3d"
                                                border.width: 1
                                                border.color: Color.accent
                                                opacity: 0.85
                                                Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                            }
                                        }

                                        // Preset: 3 windows - Columns
                                        Row {
                                            anchors.fill: parent
                                            spacing: 2
                                            visible: parent.capVal === 3 && (parent.preset === "columns" || parent.preset === "side-by-side")
                                            Repeater {
                                                model: 3
                                                Rectangle {
                                                    width: (parent.width - 4) / 3
                                                    height: parent.height
                                                    radius: 2
                                                    color: Color.accentContainer || "#262b3d"
                                                    border.width: 1
                                                    border.color: Color.accent
                                                    opacity: 0.85
                                                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                                }
                                            }
                                        }

                                        // Preset: 3 windows - Master Left
                                        Row {
                                            anchors.fill: parent
                                            spacing: 2
                                            visible: parent.capVal === 3 && parent.preset === "master-left"
                                            Rectangle {
                                                width: (parent.width - 2) / 2
                                                height: parent.height
                                                radius: 2
                                                color: Color.accentContainer || "#262b3d"
                                                border.width: 1
                                                border.color: Color.accent
                                                opacity: 0.85
                                                Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                            }
                                            Column {
                                                width: (parent.width - 2) / 2
                                                height: parent.height
                                                spacing: 2
                                                Rectangle {
                                                    width: parent.width
                                                    height: (parent.height - 2) / 2
                                                    radius: 2
                                                    color: Color.accentContainer || "#262b3d"
                                                    border.width: 1
                                                    border.color: Color.accent
                                                    opacity: 0.85
                                                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                                }
                                                Rectangle {
                                                    width: parent.width
                                                    height: (parent.height - 2) / 2
                                                    radius: 2
                                                    color: Color.accentContainer || "#262b3d"
                                                    border.width: 1
                                                    border.color: Color.accent
                                                    opacity: 0.85
                                                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                                }
                                            }
                                        }

                                        // Preset: 3 windows - Master Right
                                        Row {
                                            anchors.fill: parent
                                            spacing: 2
                                            visible: parent.capVal === 3 && parent.preset === "master-right"
                                            Column {
                                                width: (parent.width - 2) / 2
                                                height: parent.height
                                                spacing: 2
                                                Rectangle {
                                                    width: parent.width
                                                    height: (parent.height - 2) / 2
                                                    radius: 2
                                                    color: Color.accentContainer || "#262b3d"
                                                    border.width: 1
                                                    border.color: Color.accent
                                                    opacity: 0.85
                                                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                                }
                                                Rectangle {
                                                    width: parent.width
                                                    height: (parent.height - 2) / 2
                                                    radius: 2
                                                    color: Color.accentContainer || "#262b3d"
                                                    border.width: 1
                                                    border.color: Color.accent
                                                    opacity: 0.85
                                                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                                }
                                            }
                                            Rectangle {
                                                width: (parent.width - 2) / 2
                                                height: parent.height
                                                radius: 2
                                                color: Color.accentContainer || "#262b3d"
                                                border.width: 1
                                                border.color: Color.accent
                                                opacity: 0.85
                                                Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                            }
                                        }

                                        // Preset: 4 windows - Columns
                                        Row {
                                            anchors.fill: parent
                                            spacing: 2
                                            visible: parent.capVal === 4 && parent.preset === "columns"
                                            Repeater {
                                                model: 4
                                                Rectangle {
                                                    width: (parent.width - 6) / 4
                                                    height: parent.height
                                                    radius: 2
                                                    color: Color.accentContainer || "#262b3d"
                                                    border.width: 1
                                                    border.color: Color.accent
                                                    opacity: 0.85
                                                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                                }
                                            }
                                        }

                                        // Preset: 4 windows - Grid
                                        Grid {
                                            anchors.fill: parent
                                            columns: 2
                                            spacing: 2
                                            visible: parent.capVal === 4 && parent.preset !== "columns" && parent.preset !== "none"
                                            Repeater {
                                                model: 4
                                                Rectangle {
                                                    width: (parent.width - 2) / 2
                                                    height: (parent.height - 2) / 2
                                                    radius: 2
                                                    color: Color.accentContainer || "#262b3d"
                                                    border.width: 1
                                                    border.color: Color.accent
                                                    opacity: 0.85
                                                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: Color.accent }
                                                }
                                            }
                                        }

                                        // Preset: Native dwindle or none
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: parent.preset === "none"
                                            radius: 2
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Color.foreground
                                            opacity: 0.4
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Native"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                                opacity: 0.6
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Mode Selector and controls for individual workspace
            Item {
                visible: root.selectedWorkspace > 0
                width: parent.width
                implicitHeight: selectedCol.implicitHeight

                Column {
                    id: selectedCol
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                        text: "WORKSPACE " + root.selectedWorkspace + (root.selectedWorkspace === root.currentWsId ? " (ACTIVE)" : "")
                        color: Color.foreground
                        opacity: 0.65
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                    }

                    // Mode Switcher (Presets vs App Presets)
                    Row {
                        width: parent.width
                        spacing: Style.space(6)
                        Ui.Button {
                            width: (parent.width - Style.space(6)) / 2
                            text: "Presets"
                            selected: root.activeWorkspaceTab === "presets"
                            bordered: true
                            focusable: true
                            onClicked: root.setWorkspaceMode(root.selectedWorkspace, "auto")
                            onRightClicked: root.showHint("Presets Mode", "Dynamic automatic tiling. Newly opened windows overflow to the next workspace once the limit is reached.", "Tip: Select from geometric presets like Side-by-Side, Columns, Master, or Grid.")
                            tooltipText: "Presets: geometric tiling layout presets with automatic overflow"
                        }
                        Ui.Button {
                            width: (parent.width - Style.space(6)) / 2
                            text: "App Presets"
                            selected: root.activeWorkspaceTab === "manual"
                            bordered: true
                            focusable: true
                            onClicked: root.setWorkspaceMode(root.selectedWorkspace, "manual")
                            onRightClicked: root.showHint("App Presets Mode", "Switches this workspace to manual editing immediately. Open, close and arrange windows freely, with or without a saved preset.", "Tip: Save captures your changes; Restore explicitly reapplies the saved apps and layout.")
                            tooltipText: "App Presets: edit windows freely; save or restore when ready"
                        }
                    }

                    // PRESETS CONTROLS
                    Column {
                        visible: root.activeWorkspaceTab === "presets"
                        width: parent.width
                        spacing: Style.space(6)

                        Ui.Button {
                            visible: !root.isWorkspaceNative(root.selectedWorkspace) && root.hasCustomCap(root.selectedWorkspace)
                            width: parent.width
                            text: "Reset workspace " + root.selectedWorkspace + " to default (" + root.cap + ")"
                            bordered: true
                            focusable: true
                            fontSize: Style.font.caption
                            onClicked: root.resetWorkspaceCap(root.selectedWorkspace)
                            onRightClicked: root.showHint("Reset Limit to Default", "Removes the custom window limit for Workspace " + root.selectedWorkspace + ", restoring the global default (" + root.cap + " windows).", "")
                        }
                        Grid {
                            width: parent.width
                            columns: 4
                            spacing: Style.space(6)
                            Repeater {
                                model: 4
                                Ui.Button {
                                    required property int index
                                    width: (content.width - Style.space(18)) / 4
                                    text: String(index + 1)
                                    selected: root.selectedWindowCap(root.selectedWorkspace) === index + 1
                                    bordered: true
                                    focusable: true
                                    onClicked: root.setWorkspaceCap(root.selectedWorkspace, index + 1)
                                    onRightClicked: root.showHint("Window Limit: " + (index + 1), "Sets the maximum number of tiled windows allowed on Workspace " + root.selectedWorkspace + " before new windows are routed to the next free workspace.", "Tip: 2 windows is recommended for coding or document reference.")
                                    Accessible.name: (index + 1) + " windows"
                                }
                            }
                        }

                        Text {
                            text: "LAYOUT PRESET"
                            color: Color.foreground
                            opacity: 0.65
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.letterSpacing: 1
                        }

                        // Reset Preset or None Controls
                        Row {
                            width: parent.width
                            spacing: Style.space(6)

                            Ui.Button {
                                visible: root.hasCustomPreset(root.selectedWorkspace)
                                width: (parent.width - Style.space(6)) / 2
                                text: "Reset to default"
                                bordered: true
                                focusable: true
                                fontSize: Style.font.caption
                                onClicked: root.removeWorkspaceAutoPreset(root.selectedWorkspace)
                                onRightClicked: root.showHint("Reset Layout Preset", "Reverts Workspace " + root.selectedWorkspace + " to the default layout preset for its window limit.", "")
                                tooltipText: "Reset to default (" + root.autoPresetLabel(root.defaultAutoPresetFor(root.effectiveCapFor(root.selectedWorkspace))) + ")"
                            }

                            Ui.Button {
                                width: root.hasCustomPreset(root.selectedWorkspace) ? ((parent.width - Style.space(6)) / 2) : parent.width
                                text: root.autoPresetForWorkspace(root.selectedWorkspace) === "none" ? "✓ Native (No Preset)" : "✕ No Preset (Native)"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "none"
                                bordered: true
                                focusable: true
                                fontSize: Style.font.caption
                                onClicked: root.setWorkspaceAutoPreset(root.selectedWorkspace, "none")
                                onRightClicked: root.showHint("Native Layout (No Preset)", "Uses native Hyprland tiling without a window limit or automatic overflow. Open and close as many windows as you like.", "")
                                tooltipText: "Native tiling on Workspace " + root.selectedWorkspace + ": no window limit or automatic overflow"
                            }
                        }

                        // Presets for Cap = 2
                        Row {
                            visible: root.effectiveCapFor(root.selectedWorkspace) === 2
                            width: parent.width
                            spacing: Style.space(6)
                            Ui.Button {
                                width: (parent.width - Style.space(6)) / 2
                                text: "⬌ Side-by-Side"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "side-by-side"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "side-by-side")
                                onRightClicked: root.showHint("Side-by-Side Preset", "Arranges 2 windows into two equal vertical columns side-by-side (left and right).", "Tip: Click again to toggle back to native layout.")
                                tooltipText: "Side-by-side columns (left and right). Click again or Reset to remove preset."
                            }
                            Ui.Button {
                                width: (parent.width - Style.space(6)) / 2
                                text: "⬍ Stacked"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "stacked"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "stacked")
                                onRightClicked: root.showHint("Stacked Preset", "Arranges 2 windows into two horizontal rows stacked vertically (top and bottom).", "Tip: Great for vertical monitors or wide Ultrawides.")
                                tooltipText: "Vertically stacked rows (top and bottom). Click again or Reset to remove preset."
                            }
                        }

                        // Presets for Cap = 3
                        Row {
                            visible: root.effectiveCapFor(root.selectedWorkspace) === 3
                            width: parent.width
                            spacing: Style.space(12)
                            Ui.Button {
                                width: (parent.width - Style.space(12)) / 3
                                text: "◨ Master L"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-left"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-left")
                                onRightClicked: root.showHint("Master Left Preset", "Positions 1 large master window on the left and 2 stacked windows on the right.", "Tip: Perfect for editor on left and terminal/browser on right.")
                                tooltipText: "1 master on left, 2 stacked on right. Click again or Reset to remove preset."
                            }
                            Ui.Button {
                                width: (parent.width - Style.space(12)) / 3
                                text: "◧ Master R"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-right"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-right")
                                onRightClicked: root.showHint("Master Right Preset", "Positions 1 large master window on the right and 2 stacked windows on the left.", "")
                                tooltipText: "2 stacked on left, 1 master on right. Click again or Reset to remove preset."
                            }
                            Ui.Button {
                                width: (parent.width - Style.space(12)) / 3
                                text: "||| Columns"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "columns"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "columns")
                                onRightClicked: root.showHint("Columns Preset (3)", "Divides the workspace into 3 equal side-by-side vertical columns across your display.", "Tip: Ideal for multi-column terminal or document monitoring.")
                                tooltipText: "3 columns side-by-side. Click again or Reset to remove preset."
                            }
                        }

                        // Presets for Cap = 4
                        Grid {
                            visible: root.effectiveCapFor(root.selectedWorkspace) === 4
                            width: parent.width
                            columns: 2
                            spacing: Style.space(6)
                            Ui.Button {
                                width: (content.width - Style.space(6)) / 2
                                text: "▦ 2×2 Grid"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "grid"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "grid")
                                onRightClicked: root.showHint("2×2 Grid Preset", "Arranges 4 windows into a balanced four-quadrant 2×2 grid.", "")
                                tooltipText: "2×2 grid arrangement. Click again or Reset to remove preset."
                            }
                            Ui.Button {
                                width: (content.width - Style.space(6)) / 2
                                text: "◨ Master L"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-left"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-left")
                                onRightClicked: root.showHint("Master Left Preset", "1 large master window on the left, with 3 stacked windows on the right.", "")
                                tooltipText: "1 master on left, 3 stacked on right. Click again or Reset to remove preset."
                            }
                            Ui.Button {
                                width: (content.width - Style.space(6)) / 2
                                text: "◧ Master R"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-right"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-right")
                                onRightClicked: root.showHint("Master Right Preset", "1 large master window on the right, with 3 stacked windows on the left.", "")
                                tooltipText: "3 stacked on left, 1 master on right. Click again or Reset to remove preset."
                            }
                            Ui.Button {
                                width: (content.width - Style.space(6)) / 2
                                text: "|||| Columns"
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "columns"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "columns")
                                onRightClicked: root.showHint("Columns Preset (4)", "Divides the workspace into 4 equal side-by-side vertical columns across your display.", "")
                                tooltipText: "4 columns side-by-side. Click again or Reset to remove preset."
                            }
                        }
                    }

                    // APP PRESETS CONTROLS
                    Column {
                        visible: root.activeWorkspaceTab === "manual"
                        width: parent.width
                        spacing: Style.space(8)

                        // Layout Snapshot Info Card
                        Rectangle {
                            width: parent.width
                            implicitHeight: snapshotCol.implicitHeight + Style.space(16)
                            radius: Style.space(6)
                            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                            border.width: 1
                            border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)

                            Column {
                                id: snapshotCol
                                anchors.fill: parent
                                anchors.margins: Style.space(8)
                                spacing: Style.space(6)

                                Text {
                                    text: root.hasSavedLayout(root.selectedWorkspace)
                                        ? "App Preset: " + root.savedLayoutSummary(root.selectedWorkspace)
                                        : "No App Preset saved yet"
                                    color: Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    text: "× removes an app from the App Preset; it does not close its open windows."
                                    wrapMode: Text.Wrap
                                    color: Color.foreground
                                    opacity: 0.65
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    visible: root.savedAppsFor(root.selectedWorkspace).length > 0
                                }

                                // App chips
                                Flow {
                                    id: appChips
                                    width: parent.width
                                    spacing: Style.space(4)
                                    visible: root.savedAppsFor(root.selectedWorkspace).length > 0

                                    Repeater {
                                        model: root.savedAppsFor(root.selectedWorkspace)
                                        Rectangle {
                                            id: chipRect
                                            required property var modelData
                                            required property int index
                                            height: Style.space(24)
                                            readonly property real fixedWidth: Style.space(isMissing ? 72 : 54)
                                            width: Math.min(appChips.width, chipName.implicitWidth + fixedWidth)
                                            radius: Style.space(4)
                                            readonly property bool isMissing: root.isAppFailed(root.selectedWorkspace, modelData)
                                            color: isMissing
                                                ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15)
                                                : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                                            border.width: 1
                                            border.color: isMissing
                                                ? Color.urgent
                                                : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)

                                            Row {
                                                id: chipRow
                                                width: parent.width - Style.space(12)
                                                anchors.centerIn: parent
                                                spacing: Style.space(4)

                                                Text {
                                                    visible: chipRect.isMissing
                                                    width: Style.space(14)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "⚠️"
                                                    font.pixelSize: Style.font.caption
                                                }

                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Style.space(14)
                                                    height: Style.space(14)
                                                    sourceSize.width: Style.space(14)
                                                    sourceSize.height: Style.space(14)
                                                    source: root.resolveIcon(chipRect.modelData.icon)
                                                    smooth: true
                                                }

                                                Text {
                                                    id: chipName
                                                    width: Math.max(0, chipRect.width - chipRect.fixedWidth)
                                                    elide: Text.ElideRight
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: chipRect.modelData.name || chipRect.modelData.class || "App"
                                                    color: chipRect.isMissing ? Color.urgent : Color.foreground
                                                    font.family: Style.font.family
                                                    font.pixelSize: Style.font.caption
                                                }

                                                // ✕ Remove button on chip
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Style.space(20)
                                                    height: Style.space(20)
                                                    radius: width / 2
                                                    color: chipMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.25) : "transparent"

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✕"
                                                        color: Color.foreground
                                                        opacity: chipMouse.containsMouse ? 1.0 : 0.6
                                                        font.pixelSize: Style.font.caption
                                                    }

                                                    MouseArea {
                                                        id: chipMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.removeSavedApp(root.selectedWorkspace, chipRect.index)
                                                    }
                                                    Ui.PanelToolTip {
                                                        visible: chipMouse.containsMouse
                                                        text: "Remove " + (chipRect.modelData.name || chipRect.modelData.class || "app") + " from saved layout"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    readonly property string failureText: root.restoreFailureText(root.selectedWorkspace)
                                    visible: failureText !== ""
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: "Last restore failed:\n" + failureText + "\nOpen the app manually and try Restore App Preset again. The × removes it from the saved preset."
                                    color: Color.urgent
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }

                                Text {
                                    visible: !root.hasSavedLayout(root.selectedWorkspace)
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: "Open and arrange windows on Workspace " + root.selectedWorkspace + ", then click 'Save Current Layout' below."
                                    color: Color.foreground
                                    opacity: 0.65
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }

                        // Conflict Resolution Card (Visible when conflicting windows are found on restore)
                        Rectangle {
                            visible: root.restoreConflict && root.restoreConflict.workspace === root.selectedWorkspace
                            width: parent.width
                            implicitHeight: conflictCol.implicitHeight + Style.space(16)
                            radius: Style.space(6)
                            color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.1)
                            border.width: 1
                            border.color: Color.urgent

                            Column {
                                id: conflictCol
                                anchors.fill: parent
                                anchors.margins: Style.space(8)
                                spacing: Style.space(6)

                                Row {
                                    width: parent.width
                                    spacing: Style.space(4)
                                    Text {
                                        text: "⚠️"
                                        font.pixelSize: Style.font.bodySmall
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Existing Windows on Workspace " + (root.restoreConflict ? root.restoreConflict.workspace : "")
                                        color: Color.urgent
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: "Workspace has " + (root.restoreConflict ? root.restoreConflict.conflict_count : 0) + " open window(s) not in this preset:"
                                    color: Color.foreground
                                    opacity: 0.85
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    wrapMode: Text.Wrap
                                }

                                // Conflict item badges
                                Flow {
                                    width: parent.width
                                    spacing: Style.space(4)
                                    Repeater {
                                        model: root.restoreConflict ? root.restoreConflict.conflicts : []
                                        Rectangle {
                                            required property var modelData
                                            height: Style.space(20)
                                            width: Math.min(conflictCol.width, conflictTxt.implicitWidth + Style.space(12))
                                            radius: Style.space(3)
                                            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                                            border.width: 1
                                            border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                                            Text {
                                                id: conflictTxt
                                                anchors.centerIn: parent
                                                width: parent.width - Style.space(8)
                                                text: modelData.title ? (modelData.class + " (" + modelData.title + ")") : (modelData.class || "Window")
                                                elide: Text.ElideMiddle
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption - 1
                                            }
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: "How would you like to handle them before restoring?"
                                    color: Color.foreground
                                    opacity: 0.85
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }

                                // Action buttons for conflict
                                Column {
                                    width: parent.width
                                    spacing: Style.space(4)

                                    Row {
                                        width: parent.width
                                        spacing: Style.space(6)
                                        Ui.Button {
                                            width: (parent.width - Style.space(6)) / 2
                                            text: "➜ Move to WS " + (root.restoreConflict ? root.restoreConflict.next_free_workspace : "")
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: root.restoreWorkspaceApps(root.selectedWorkspace, "move")
                                            onRightClicked: root.showHint("Move Conflicting Windows", "Moves all extra open windows from Workspace " + root.selectedWorkspace + " to empty Workspace " + (root.restoreConflict ? root.restoreConflict.next_free_workspace : "") + ", sends a desktop notification, and restores the preset.", "")
                                            tooltipText: "Move conflicting windows to the next empty workspace (with desktop notification)"
                                        }
                                        Ui.Button {
                                            width: (parent.width - Style.space(6)) / 2
                                            text: "✕ Close"
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: root.restoreWorkspaceApps(root.selectedWorkspace, "close")
                                            onRightClicked: root.showHint("Close Conflicting Windows", "Closes the extra open windows on Workspace " + root.selectedWorkspace + " and restores the saved preset.", "")
                                            tooltipText: "Close existing windows and restore the saved layout"
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Style.space(6)
                                        Ui.Button {
                                            width: (parent.width - Style.space(6)) / 2
                                            text: "◻ Keep (Float)"
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: root.restoreWorkspaceApps(root.selectedWorkspace, "keep")
                                            onRightClicked: root.showHint("Keep Conflicting Windows", "Floats the extra open windows on Workspace " + root.selectedWorkspace + " so they remain visible without breaking the tiled preset layout.", "")
                                            tooltipText: "Keep existing windows on this workspace as floating windows"
                                        }
                                        Ui.Button {
                                            width: (parent.width - Style.space(6)) / 2
                                            text: "Cancel"
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: {
                                                root.restoreConflict = null
                                                root.lastMessage = "Restore cancelled."
                                            }
                                            onRightClicked: root.showHint("Cancel Restore", "Aborts restoring the App Preset and leaves all windows as they are.", "")
                                            tooltipText: "Cancel restoring this preset"
                                        }
                                    }
                                }
                            }
                        }

                        // Action Buttons
                        Row {
                            width: parent.width
                            spacing: Style.space(6)

                            Ui.Button {
                                width: (root.hasSavedLayout(root.selectedWorkspace) && root.savedAppsFor(root.selectedWorkspace).length > 0)
                                    ? (parent.width - Style.space(6)) / 2
                                    : parent.width
                                text: "Save App Preset"
                                bordered: true
                                focusable: true
                                onClicked: root.captureWorkspaceLayout(root.selectedWorkspace)
                                onRightClicked: root.showHint("Save App Preset", "Snapshots all open windows on Workspace " + root.selectedWorkspace + ", including positions, sizes, desktop files, and launch commands.", "Tip: Open and arrange your apps first, then click here to save.")
                                tooltipText: "Snapshot current windows and arranged positions as App Preset on Workspace " + root.selectedWorkspace
                            }

                            Ui.Button {
                                visible: root.hasSavedLayout(root.selectedWorkspace) && root.savedAppsFor(root.selectedWorkspace).length > 0
                                width: (parent.width - Style.space(6)) / 2
                                text: "Restore App Preset"
                                bordered: true
                                focusable: true
                                onClicked: root.restoreWorkspaceApps(root.selectedWorkspace)
                                onRightClicked: root.showHint("Restore App Preset", "Relaunches missing apps and restores windows into their exact saved arrangement. If conflicting windows are open, you will be prompted.", "Tip: Enable 'Auto-move on restore' in settings to auto-move conflicts.")
                                tooltipText: "Launch missing apps and restore window layout for Workspace " + root.selectedWorkspace
                            }
                        }

                        // Toggles
                        Ui.Toggle {
                            width: parent.width
                            label: "Save apps & show icons"
                            description: "Display app icons in the workspace bar card"
                            checked: root.workspaceSaveApps(root.selectedWorkspace)
                            onClicked: root.toggleWorkspaceSaveApps(root.selectedWorkspace)

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: root.showHint("Save Apps & Show Icons", "Saves the application desktop entries with the layout and displays their app icons on the workspace card.", "")
                            }
                        }

                        Ui.Toggle {
                            width: parent.width
                            label: "Autostart on session startup"
                            description: "Automatically launch saved apps on startup"
                            checked: root.workspaceAutostart(root.selectedWorkspace)
                            onClicked: root.toggleWorkspaceAutostart(root.selectedWorkspace)

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: root.showHint("Autostart on Startup", "Automatically launches this workspace's saved applications into their saved positions when you log into your desktop session.", "Tip: Set this on daily-driver workspaces for instant readiness.")
                            }
                        }

                        Ui.Button {
                            visible: root.hasSavedLayout(root.selectedWorkspace)
                            width: parent.width
                            text: "Clear App Preset"
                            bordered: true
                            focusable: true
                            fontSize: Style.font.caption
                            onClicked: root.clearWorkspaceLayout(root.selectedWorkspace)
                            onRightClicked: root.showHint("Clear App Preset", "Deletes the saved layout for Workspace " + root.selectedWorkspace + " and returns it to automatic Presets mode. Open windows remain open.", "")
                        }
                    }
                }
            }

            // Global limit controls (when All Workspaces is selected)
            Column {
                visible: root.selectedWorkspace === 0
                width: parent.width
                spacing: Style.space(6)

                Text {
                    text: "DEFAULT WINDOW LIMIT (ALL WORKSPACES)"
                    color: Color.foreground
                    opacity: 0.65
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                }

                Grid {
                    width: parent.width
                    columns: 4
                    spacing: Style.space(6)
                    Repeater {
                        model: 4
                        Ui.Button {
                            required property int index
                            width: (content.width - Style.space(18)) / 4
                            text: String(index + 1)
                            selected: root.cap === index + 1
                            bordered: true
                            focusable: true
                            onClicked: root.updateSetting("maxWindows", index + 1)
                            onRightClicked: root.showHint("Global Limit: " + (index + 1), "Sets the default maximum window limit (" + (index + 1) + " windows) applied to all workspaces without custom overrides.", "")
                            Accessible.name: (index + 1) + " windows"
                        }
                    }
                }

                Text {
                    visible: root.cap > 1
                    text: "DEFAULT LAYOUT PRESET"
                    color: Color.foreground
                    opacity: 0.65
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                }

                // Default Preset choices for Cap = 2
                Row {
                    visible: root.cap === 2
                    width: parent.width
                    spacing: Style.space(6)
                    Ui.Button {
                        width: (parent.width - Style.space(6)) / 2
                        text: "⬌ Side-by-Side"
                        selected: (root.defaultAutoPresets["2"] || "side-by-side") === "side-by-side"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("2", "side-by-side")
                        onRightClicked: root.showHint("Default Preset (Side-by-Side)", "Sets side-by-side columns as the default layout preset for 2 windows across all workspaces.", "")
                        tooltipText: "Default to side-by-side columns"
                    }
                    Ui.Button {
                        width: (parent.width - Style.space(6)) / 2
                        text: "⬍ Stacked"
                        selected: root.defaultAutoPresets["2"] === "stacked"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("2", "stacked")
                        onRightClicked: root.showHint("Default Preset (Stacked)", "Sets stacked rows as the default layout preset for 2 windows across all workspaces.", "")
                        tooltipText: "Default to vertically stacked rows"
                    }
                }

                // Default Preset choices for Cap = 3
                Row {
                    visible: root.cap === 3
                    width: parent.width
                    spacing: Style.space(6)
                    Ui.Button {
                        width: (parent.width - Style.space(12)) / 3
                        text: "◨ Master L"
                        selected: (root.defaultAutoPresets["3"] || "master-left") === "master-left"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("3", "master-left")
                        onRightClicked: root.showHint("Default Preset (Master Left)", "Sets 1 master on left, 2 stacked on right as the default layout preset for 3 windows.", "")
                        tooltipText: "Default to 1 master on left, 2 stacked on right"
                    }
                    Ui.Button {
                        width: (parent.width - Style.space(12)) / 3
                        text: "◧ Master R"
                        selected: root.defaultAutoPresets["3"] === "master-right"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("3", "master-right")
                        onRightClicked: root.showHint("Default Preset (Master Right)", "Sets 1 master on right, 2 stacked on left as the default layout preset for 3 windows.", "")
                        tooltipText: "Default to 2 stacked on left, 1 master on right"
                    }
                    Ui.Button {
                        width: (parent.width - Style.space(12)) / 3
                        text: "||| Columns"
                        selected: root.defaultAutoPresets["3"] === "columns"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("3", "columns")
                        onRightClicked: root.showHint("Default Preset (Columns)", "Sets 3 equal side-by-side vertical columns as the default layout preset for 3 windows.", "")
                        tooltipText: "Default to 3 columns side-by-side"
                    }
                }

                // Default Preset choices for Cap = 4
                Grid {
                    visible: root.cap === 4
                    width: parent.width
                    columns: 2
                    spacing: Style.space(6)
                    Ui.Button {
                        width: (content.width - Style.space(6)) / 2
                        text: "▦ 2×2 Grid"
                        selected: (root.defaultAutoPresets["4"] || "grid") === "grid"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "grid")
                        onRightClicked: root.showHint("Default Preset (2×2 Grid)", "Sets 2×2 four-quadrant grid as the default layout preset for 4 windows.", "")
                        tooltipText: "Default to 2×2 grid"
                    }
                    Ui.Button {
                        width: (content.width - Style.space(6)) / 2
                        text: "◨ Master L"
                        selected: root.defaultAutoPresets["4"] === "master-left"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "master-left")
                        onRightClicked: root.showHint("Default Preset (Master Left)", "Sets 1 master on left, 3 stacked on right as the default layout preset for 4 windows.", "")
                        tooltipText: "Default to master on left"
                    }
                    Ui.Button {
                        width: (content.width - Style.space(6)) / 2
                        text: "◧ Master R"
                        selected: root.defaultAutoPresets["4"] === "master-right"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "master-right")
                        onRightClicked: root.showHint("Default Preset (Master Right)", "Sets 1 master on right, 3 stacked on left as the default layout preset for 4 windows.", "")
                        tooltipText: "Default to master on right"
                    }
                    Ui.Button {
                        width: (content.width - Style.space(6)) / 2
                        text: "|||| Columns"
                        selected: root.defaultAutoPresets["4"] === "columns"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "columns")
                        onRightClicked: root.showHint("Default Preset (Columns)", "Sets 4 equal side-by-side vertical columns as the default layout preset for 4 windows.", "")
                        tooltipText: "Default to 4 columns side-by-side"
                    }
                }
            }

            Ui.Toggle {
                width: parent.width
                label: "Right-click help hints"
                description: "Show explanations & tips when right-clicking controls"
                checked: root.rightClickHintsEnabled
                onClicked: root.updateSetting("rightClickHints", !root.rightClickHintsEnabled)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: root.showHint("Right-Click Hints", "Toggle contextual help hints on right-click across all controls in the plugin.", "Tip: You can turn this off anytime if you prefer quiet operation.")
                }
            }

            Ui.Toggle {
                width: parent.width
                label: "Auto-move on restore"
                description: "Move existing windows to next free workspace without asking"
                checked: root.autoMoveOnRestore
                onClicked: root.updateSetting("autoMoveOnRestore", !root.autoMoveOnRestore)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: root.showHint("Auto-Move On Restore", "When restoring an App Preset on an occupied workspace, automatically move existing windows to the next empty workspace with a desktop notification.", "Tip: Ideal for fast, seamless multi-app switching.")
                }
            }

            Text {
                width: parent.width
                text: root.failed ? root.lastMessage : (root.tilingActive ? root.lastMessage : "Your windows stay where you put them.")
                wrapMode: Text.Wrap
                color: root.failed ? Color.urgent : Color.foreground
                opacity: root.failed ? 1 : 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
            } // end workspaceControlsView

            // USER MANUAL VIEW (Visible when showManualView is true)
            Column {
                id: manualView
                visible: root.showManualView
                width: parent.width
                spacing: Style.space(10)

                Ui.Button {
                    width: parent.width
                    text: "← Back to Workspace Controls"
                    bordered: true
                    focusable: true
                    onClicked: root.showManualView = false
                }

                // Section 1: Presets
                Rectangle {
                    width: parent.width
                    implicitHeight: sec1Col.implicitHeight + Style.space(16)
                    radius: Style.space(6)
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)

                    Column {
                        id: sec1Col
                        anchors.fill: parent
                        anchors.margins: Style.space(8)
                        spacing: Style.space(4)

                        Text {
                            text: "1. Presets (Dynamic Tiling & Overflow)"
                            color: Theme.Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Theme.Style.font.bodySmall
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: "• Sets a window limit (1 to 4) per workspace or globally.\n• When full, newly opened windows automatically move to the next free workspace.\n• Choose layout presets: Side-by-Side (2), Stacked (2), Master Left/Right (3-4), Columns (3-4), or 2×2 Grid (4).\n• Manual moves (Super+Shift+<number>) intentionally override the limit."
                            color: Color.foreground
                            opacity: 0.85
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Section 2: App Presets
                Rectangle {
                    width: parent.width
                    implicitHeight: sec2Col.implicitHeight + Style.space(16)
                    radius: Style.space(6)
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)

                    Column {
                        id: sec2Col
                        anchors.fill: parent
                        anchors.margins: Style.space(8)
                        spacing: Style.space(4)

                        Text {
                            text: "2. App Presets (Saved Workspaces)"
                            color: Theme.Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Theme.Style.font.bodySmall
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: "• Lets you open, close and arrange windows freely, even without a saved preset.\n• Disables automatic overflow moves so your arranged layout is preserved.\n• Open and arrange your apps, then click 'Save App Preset'.\n• Click 'Restore App Preset' anytime to relaunch and restore layout.\n• Enable 'Autostart' to launch them automatically on session login."
                            color: Color.foreground
                            opacity: 0.85
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Section 3: Conflict Handling
                Rectangle {
                    width: parent.width
                    implicitHeight: sec3Col.implicitHeight + Style.space(16)
                    radius: Style.space(6)
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)

                    Column {
                        id: sec3Col
                        anchors.fill: parent
                        anchors.margins: Style.space(8)
                        spacing: Style.space(4)

                        Text {
                            text: "3. Conflict Resolution on Restore"
                            color: Theme.Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Theme.Style.font.bodySmall
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: "If open windows already occupy a workspace when restoring an App Preset:\n• Move: Shifts them to the next free workspace (with notification).\n• Close: Closes the conflicting windows.\n• Keep: Floats them so they stay without breaking the tiled preset.\n• Tip: Turn on 'Auto-move on restore' in settings to auto-move without prompting."
                            color: Color.foreground
                            opacity: 0.85
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Section 4: Right-Click Hints & Shortcuts
                Rectangle {
                    width: parent.width
                    implicitHeight: sec4Col.implicitHeight + Style.space(16)
                    radius: Style.space(6)
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)

                    Column {
                        id: sec4Col
                        anchors.fill: parent
                        anchors.margins: Style.space(8)
                        spacing: Style.space(4)

                        Text {
                            text: "4. Right-Click Hints & Shortcuts"
                            color: Theme.Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Theme.Style.font.bodySmall
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: "• Right-click any button or control to display instant help and handling tips.\n• Right-click the bar icon to pause or resume Simple Tile.\n• Left-click the bar icon to toggle this settings panel.\n• Right-click hints can be toggled on/off in the settings below."
                            color: Color.foreground
                            opacity: 0.85
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Ui.Button {
                    width: parent.width
                    text: "← Back to Workspace Controls"
                    bordered: true
                    focusable: true
                    onClicked: root.showManualView = false
                }
            }
        }
        }
    }
}
