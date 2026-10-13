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
import "I18n.js" as I18n

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
    readonly property bool hasAnyAutostart: {
        if (!root.workspaceLayouts) return false
        for (var ak in root.workspaceLayouts) {
            var al = root.workspaceLayouts[ak]
            if (al && al.autostart === true) return true
        }
        return false
    }
    readonly property bool hasAutostartActive: {
        if (root.isWorkspaceManual(root.currentWsId)) {
            return root.workspaceAutostart(root.currentWsId)
        }
        return root.hasAnyAutostart
    }
    // Bar Icon Modes:
    // 1: Disabled
    // 2: Enabled, no preset defined (Native tiling)
    // 3: Enabled with defined presets
    // 4: Enabled, App Preset defined with Autostart active (Theme accent dot ● indicator)
    readonly property int currentBarIconMode: {
        if (!root.tilingActive) return 1
        if (root.hasAnyAppPreset && root.hasAutostartActive) return 4
        if (root.currentWsHasDefinedPreset) return 3
        return 2
    }
    property int selectedWorkspace: 0
    property bool opened: false
    property bool popoutSwitchClosing: false
    property string lastMessage: root.t("newWindowsMoveOn")
    property bool failed: false
    property bool autostartFinished: false
    property int autostartAttempts: 0
    property int workspacePage: 0
    readonly property var visibleWorkspaces: workspacePage === 1 ? [5, 6, 7, 8] : [1, 2, 3, 4]
    property var pending: []
    property var failedAppNames: ({})
    property var failedAppDetails: ({})
    property string activeWorkspaceTab: "presets"
    anchors.fill: parent
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property bool rightClickHintsEnabled: setting("rightClickHints", true) !== false
    readonly property bool autoMoveOnRestore: setting("autoMoveOnRestore", false) === true
    property var restoreConflict: null
    property string activeHintTitle: ""
    property string activeHintBody: ""
    property string activeHintTip: ""
    property bool showSettingsView: false
    // Interface language: the system's unless one is picked on the settings
    // page (stored in this widget's shell.json entry). Built-in translations.
    readonly property string systemLang: I18n.systemLanguage(Quickshell.env("LC_ALL"), Quickshell.env("LC_MESSAGES"), Quickshell.env("LANG"))
    readonly property string languageSetting: String(setting("language", "auto"))
    readonly property string lang: I18n.resolve(languageSetting, systemLang)
    function t(key, args) { return I18n.tr(lang, key, args) }
    function tn(key, n, args) { return I18n.trn(lang, key, n, args) }
    function setLanguage(code) {
        var entry = Object.assign({}, settings, {id: moduleName})
        if (code === "auto") delete entry.language
        else entry.language = code
        if (saveSettingsEntry(entry)) settings = entry
    }
    onShowSettingsViewChanged: { panelScroll.contentY = 0; content.forceActiveFocus() }

    Component.onCompleted: {
        Qt.callLater(function() {
            if (!root.tilingActive) {
                root.updateSetting("active", true)
            }
        })
    }

    onOpenedChanged: {
        if (!opened) showSettingsView = false
        if (opened) {
            restoreConflict = null
            if (selectedWorkspace === 0 && root.currentWsId > 0) {
                selectedWorkspace = root.currentWsId
            }
            if (root.selectedWorkspace >= 5 && root.selectedWorkspace <= 8) {
                workspacePage = 1
            } else if (root.selectedWorkspace >= 1 && root.selectedWorkspace <= 4) {
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
        if (preset === "side-by-side") return root.t("sideBySide")
        if (preset === "stacked") return root.t("stacked")
        if (preset === "master-left") return root.t("masterLeft")
        if (preset === "master-right") return root.t("masterRight")
        if (preset === "columns") return root.t("columns")
        if (preset === "grid") return root.t("grid")
        if (preset === "none") return root.t("noneNative")
        return preset || root.t("default")
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

        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
            return
        }

        if (preset === "none") {
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--remove-preset", String(wsId)]
            lastMessage = root.t("wsNativeMsg", [wsId])
        } else {
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), preset]
            lastMessage = root.t("setWsLayout", [wsId, autoPresetLabel(preset)])
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

        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
            return
        }

        var defaultPreset = defaultAutoPresetFor(effectiveCapFor(wsId))
        applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), defaultPreset]
        applyPresetWorker.running = true
        lastMessage = root.t("resetWsLayout", [wsId, autoPresetLabel(defaultPreset)])
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
        lastMessage = root.t("defaultFor", [capVal, autoPresetLabel(preset)])
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
        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            lastMessage = root.t("removedFromLayout", [removed.name || root.t("appLower")])
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveThe")
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
            window_timeout: root.t("noMatchingWindowAppeared"),
            close_timeout: root.t("closeTimeout", [wsId]),
            launch_failed: root.t("theAppCouldNot"),
            command_not_found: root.t("theSavedLaunchCommand"),
            desktop_file_not_found: root.t("theSavedAppLauncher"),
            workspace_move_failed: root.t("theWindowCouldNot"),
            app_launching_disabled: root.t("launchingMissingAppsIs")
        }
        return failures.map(function(f) {
            return (f.name || f.class || root.t("app")) + ": " + (reasons[f.reason] || f.reason || root.t("restoreFailedWithoutA"))
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
        return layout ? (layout.autostart !== false) : true
    }

    function savedLayoutSummary(wsId) {
        var layout = layoutForWorkspace(wsId)
        if (!layout) return root.t("none")
        var winCount = layout.count || (layout.windows ? layout.windows.length : 0)
        return root.tn("windowsN", winCount)
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

        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            lastMessage = root.t("setWsLimit", [wsId, newCap])
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
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

        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            lastMessage = root.t("resetWsLimit", [wsId, root.cap])
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
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
            lastMessage = root.t("wsManualMsg", [wsId])
        } else {
            var preset = autoPresetForWorkspace(wsId)
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), preset]
            applyPresetWorker.running = true
            lastMessage = preset === "none"
                ? root.t("wsNativeMsg", [wsId])
                : root.t("wsResumed", [wsId, autoPresetLabel(preset)])
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
        layout.autostart = !workspaceAutostart(wsId)
        layouts[String(wsId)] = layout
        updateSetting("workspaceLayouts", layouts)
    }

    function clearWorkspaceLayout(wsId) {
        if (!wsId || wsId <= 0) return
        var layouts = Object.assign({}, workspaceLayouts)
        delete layouts[String(wsId)]
        var modes = Object.assign({}, workspaceModes)
        delete modes[String(wsId)]
        var entry = Object.assign({}, settings, {id: moduleName})
        entry["workspaceLayouts"] = layouts
        entry["workspaceModes"] = modes
        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            activeWorkspaceTab = "presets"
            lastMessage = root.t("removedAppPresetFor", [wsId])
            var defaultPreset = autoPresetForWorkspace(wsId) || defaultAutoPresetFor(effectiveCapFor(wsId))
            if (defaultPreset && defaultPreset !== "none") {
                applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), defaultPreset]
                applyPresetWorker.running = true
            }
        }
    }

    function resetWorkspaceToDefault(wsId) {
        if (!wsId || wsId <= 0) return
        var entry = Object.assign({}, settings, {id: moduleName})
        var currentCaps = Object.assign({}, workspaceCaps)
        delete currentCaps[String(wsId)]
        entry["workspaceCaps"] = currentCaps

        var currentPresets = Object.assign({}, workspaceAutoPresets)
        delete currentPresets[String(wsId)]
        entry["workspaceAutoPresets"] = currentPresets

        var currentModes = Object.assign({}, workspaceModes)
        delete currentModes[String(wsId)]
        entry["workspaceModes"] = currentModes

        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            var defaultPreset = defaultAutoPresetFor(root.cap)
            if (defaultPreset && defaultPreset !== "none" && root.cap > 1) {
                applyPresetWorker.command = ["python3", root.helperScriptPath(), "--apply-preset", String(wsId), defaultPreset]
                applyPresetWorker.running = true
            }
            lastMessage = root.t("resetWsDefault", [wsId, root.cap, autoPresetLabel(defaultPreset)])
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
        }
    }

    function saveSettingsEntry(entry) {
        if (!bar || !bar.shell) return false
        // The shell returns false for unchanged settings as well as errors.
        var existing = Object.assign({}, settings, {id: moduleName})
        var keys = Object.keys(entry)
        var unchanged = keys.length === Object.keys(existing).length
        for (var i = 0; unchanged && i < keys.length; i++) {
            var key = keys[i]
            unchanged = JSON.stringify(existing[key]) === JSON.stringify(entry[key])
        }
        if (unchanged) return true
        return bar.shell.updateEntryInline(moduleName, entry)
    }

    function clearAllPresets() {
        var entry = Object.assign({}, settings, {id: moduleName})
        entry["workspaceCaps"] = {}
        entry["workspaceAutoPresets"] = {}
        entry["defaultAutoPresets"] = {"1": "none", "2": "none", "3": "none", "4": "none"}
        entry["workspaceModes"] = {}
        entry["workspaceLayouts"] = {}
        if (saveSettingsEntry(entry)) {
            settings = entry
            restoreConflict = null
            activeWorkspaceTab = "presets"
            failedAppNames = ({})
            failedAppDetails = ({})
            failed = false
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--remove-all-presets"]
            applyPresetWorker.running = true
            lastMessage = root.t("clearedAllLayoutAnd")
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
        }
    }

    function removeAllWorkspacePresets() {
        var entry = Object.assign({}, settings, {id: moduleName})
        var presets = {}
        for (var i = 1; i <= 10; i++) {
            presets[String(i)] = "none"
        }
        entry["workspaceAutoPresets"] = presets
        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--remove-all-presets"]
            applyPresetWorker.running = true
            lastMessage = root.t("removedLayoutPresetsFor")
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
        }
    }

    function resetAllWorkspacesToDefault() {
        var entry = Object.assign({}, settings, {id: moduleName})
        entry["workspaceCaps"] = {}
        entry["workspaceAutoPresets"] = {}
        var modes = Object.assign({}, workspaceModes)
        for (var k in modes) {
            if (modes[k] === "manual") delete modes[k]
        }
        entry["workspaceModes"] = modes
        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            applyPresetWorker.command = ["python3", root.helperScriptPath(), "--reset-all-presets"]
            applyPresetWorker.running = true
            lastMessage = root.t("resetAllDefaults", [root.cap, autoPresetLabel(defaultAutoPresetFor(root.cap))])
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
        }
    }

    function removeAllAppPresets() {
        var entry = Object.assign({}, settings, {id: moduleName})
        entry["workspaceLayouts"] = {}
        var modes = Object.assign({}, workspaceModes)
        for (var k in modes) {
            if (modes[k] === "manual") delete modes[k]
        }
        entry["workspaceModes"] = modes
        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            failedAppNames = ({})
            failedAppDetails = ({})
            lastMessage = root.t("removedAllSavedApp")
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
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
        var autostart = existing.autostart !== undefined ? existing.autostart : true
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
        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
            lastMessage = root.t("savedAppPresetFor", [wsId, res.count || 0])
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
        if (root.selectedWorkspace <= 0) {
            selectedWorkspace = root.currentWsId > 0 ? root.currentWsId : 0
        }
        opened = true
    }
    function close() {
        opened = false
    }
    function closeForPopoutSwitch() {
        popoutSwitchClosing = true
        close()
        Qt.callLater(function() { popoutSwitchClosing = false })
    }
    function togglePanel() {
        if (opened) close()
        else open()
    }
    function updateSetting(key, value) {
        if (settings[key] === value) return
        var entry = Object.assign({}, settings, {id: moduleName})
        entry[key] = value
        if (saveSettingsEntry(entry)) {
            settings = entry
            failed = false
        } else {
            failed = true
            lastMessage = root.t("couldNotSaveSettings")
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
                    if (root.failed) root.lastMessage = root.t("couldNotMoveThe")
                    else if (result.status === "moved") root.lastMessage = root.t("lastMove", [result.source, result.target])
                    else if (result.status === "manual") root.lastMessage = root.t("wsUsingAppPresets", [result.workspace])
                    if (root.failed) console.warn("Workspace Presets:", result.message)
                } catch (error) {
                    root.failed = true
                    root.lastMessage = root.t("theWindowHelperReturned")
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                root.failed = true
                root.lastMessage = root.t("windowHelperFailedCheck")
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
                        root.lastMessage = root.t("captureFailed", [res.message || root.t("unknownError")])
                    }
                } catch (e) {
                    root.failed = true
                    root.lastMessage = root.t("theCaptureHelperReturned")
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
                        root.lastMessage = root.t("wsConflicts", [res.workspace, res.conflict_count])
                    } else if (res.failed && res.failed.length > 0) {
                        root.restoreConflict = null
                        root.failed = true
                        root.recordFailedApps(res.workspace || actionWorker.targetWs, res.failed)
                        var failedNames = root.restoreFailureText(res.workspace || actionWorker.targetWs)
                        if (res.launched && res.launched.length > 0) {
                            root.lastMessage = root.t("launchedCouldNot", [res.launched.join(", "), failedNames])
                        } else {
                            root.lastMessage = root.t("couldNotRestore", [failedNames])
                        }
                    } else if (res.status === "ok") {
                        root.restoreConflict = null
                        root.failed = false
                        root.recordFailedApps(res.workspace || actionWorker.targetWs, [])
                        if (res.launched && res.launched.length > 0) {
                            root.lastMessage = root.t("launched", [res.launched.join(", ")])
                        } else if (res.already_running && res.already_running.length > 0) {
                            root.lastMessage = (res.geometry_restored ? root.t("restoredLayout") : root.t("alreadyOpen")) + res.already_running.join(", ")
                        } else {
                            root.lastMessage = root.t("actionCompleted")
                        }
                    } else if (res.message) {
                        root.failed = res.status === "error"
                        root.lastMessage = root.t("wsMessage", [actionWorker.targetWs, res.message])
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
                        if (res.action === "remove_all_presets") {
                            root.lastMessage = root.t("allWorkspacesSetTo")
                        } else if (res.action === "reset_all_presets") {
                            root.lastMessage = root.t("allResetDefault", [root.autoPresetLabel(res.default_preset)])
                        } else if (res.preset === "none") {
                            root.lastMessage = root.t("presetRemovedOn", [res.workspace])
                        } else {
                            root.lastMessage = root.t("appliedTo", [root.autoPresetLabel(res.preset), res.workspace])
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
                        root.lastMessage = root.t("someSavedWindowsCould")
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
                root.lastMessage = root.t("autostartCouldNotConnect")
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
                // AUTOSTART INDICATOR (Mode 4: Autostart ON [●])
                // Only shown when at least one app preset is defined and autostart is active
                // ==========================================
                Item {
                    visible: mode === 4 && root.tilingActive
                    x: 9.5; y: -1.5; width: 6; height: 6

                    // Solid filled dot (●) in theme accent color
                    Rectangle {
                        anchors.centerIn: parent
                        width: 5.5
                        height: 5.5
                        radius: 2.75
                        color: Color.accent
                        border.width: 1
                        border.color: Color.background

                        // Subtle outer halo when on the active app preset workspace
                        Rectangle {
                            visible: root.isWorkspaceManual(root.currentWsId)
                            anchors.centerIn: parent
                            width: parent.width + 3
                            height: parent.height + 3
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Color.accent
                            opacity: 0.60
                        }
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
                return root.t("workspacePresetsDisabledPaus")
            }
            if (root.currentBarIconMode === 2) {
                return root.t("tip2", [root.currentWsId])
            }
            if (root.currentBarIconMode === 3) {
                return root.t("tip3", [root.currentWsId, root.autoPresetLabel(root.autoPresetForWorkspace(root.currentWsId)), root.capForWorkspace(root.currentWsId)])
            }
            // Mode 4: Autostart ON
            var appCount4 = root.savedAppsFor(root.currentWsId).length
            var status4 = root.isWorkspaceManual(root.currentWsId)
                ? (root.t("tipAppActive", [root.currentWsId]) + (appCount4 > 0 ? " (" + root.t("appsSaved", [appCount4]) + ")" : ""))
                : root.t("tipPresetAuto", [root.currentWsId, root.currentWsHasDefinedPreset ? root.t("presetN", [root.autoPresetLabel(root.autoPresetForWorkspace(root.currentWsId))]) : root.t("nativeTiling")])
            return root.t("tip4", [status4])
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
            // Esc and Backspace leave the settings page first.
            Keys.onEscapePressed: { if (root.showSettingsView) root.showSettingsView = false; else root.close() }
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Backspace && root.showSettingsView) { root.showSettingsView = false; event.accepted = true }
            }

            Item {
                width: parent.width
                height: Style.space(28)

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.t("workspacePresets2")
                    color: Theme.Color.accent
                    font.family: Theme.Style.font.family
                    font.pixelSize: Theme.Style.font.title
                    font.bold: true
                }

                Ui.Button {
                    visible: !root.showSettingsView
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: Style.space(24)
                    text: "\udb81\udc93"
                    fontSize: Style.font.caption
                    bordered: true
                    focusable: true
                    onClicked: root.showSettingsView = true
                    tooltipText: root.t("settings")
                }
            }

            Text {
                width: parent.width
                text: root.t("aLittleRoomTo")
                color: Color.foreground
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            Ui.Toggle {
                visible: !root.showSettingsView
                width: parent.width
                label: root.tilingActive ? root.t("tilingActive") : root.t("tilingPaused")
                description: root.t("moveNewWindowsWhen")
                checked: root.tilingActive
                onClicked: root.updateSetting("active", !root.tilingActive)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: root.showHint(root.t("tilingActiveToggle"), root.t("temporarilyPauseOrResume"), root.t("tipYouCanAlso"))
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
                            tooltipText: root.t("dismissHint")
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

            // SETTINGS VIEW: language and the global behaviour switches.
            Column {
                id: settingsView
                visible: root.showSettingsView
                width: parent.width
                spacing: Style.space(12)

                Row {
                    spacing: Style.space(12)
                    Ui.Button {
                        focusable: true
                        bordered: true
                        iconText: "\udb80\udc4d"
                        text: root.t("back") + " · \u232b"
                        tooltipText: root.t("backTip")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: { root.showSettingsView = false; content.forceActiveFocus() }
                    }
                    Text { textFormat: Text.PlainText; text: root.t("settings").toUpperCase(); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1; anchors.verticalCenter: parent.verticalCenter }
                }
                Ui.PanelSeparator { width: parent.width }

                Row {
                    spacing: Style.space(10)
                    Text { id: languageLabel; textFormat: Text.PlainText; width: Style.space(90); text: root.t("language"); color: Color.foreground; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                    CompactDropdown {
                        id: languagePicker
                        anchors.verticalCenter: parent.verticalCenter
                        showLabel: false
                        // Wide enough for the longest option, plus padding and the chevron.
                        width: fitWidth
                        fontSize: Style.font.caption
                        rowHeight: languageLabel.implicitHeight + Style.space(6)
                        popupRowHeight: languageLabel.implicitHeight + Style.space(8)
                        options: [{ value: "auto", label: root.t("systemLanguage", [I18n.languageName(root.systemLang)]) }]
                            .concat(I18n.LANGUAGES.map(function(l) { return { value: l.code, label: l.name } }))
                        value: root.languageSetting
                        // Picking cuts the value binding inside the dropdown; restore it.
                        onChanged: function(picked) {
                            root.setLanguage(picked)
                            languagePicker.value = Qt.binding(function() { return root.languageSetting })
                        }
                    }
                }

                Ui.Toggle {
                    width: parent.width
                    label: root.t("rightClickHelpHints")
                    description: root.t("showExplanationsTipsWhen")
                    checked: root.rightClickHintsEnabled
                    onClicked: root.updateSetting("rightClickHints", !root.rightClickHintsEnabled)

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: root.showHint(root.t("rightClickHints"), root.t("toggleContextualHelpHints"), root.t("tipYouCanTurn"))
                    }
                }

                Ui.Toggle {
                    width: parent.width
                    label: root.t("autoMoveOnRestore")
                    description: root.t("moveExistingWindowsTo")
                    checked: root.autoMoveOnRestore
                    onClicked: root.updateSetting("autoMoveOnRestore", !root.autoMoveOnRestore)

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: root.showHint(root.t("autoMoveOnRestore2"), root.t("whenRestoringAnApp"), root.t("tipIdealForFast"))
                    }
                }

            }

            // MAIN WORKSPACE CONTROLS VIEW (hidden while the settings view is open)
            Column {
                id: workspaceControlsView
                visible: !root.showSettingsView
                width: parent.width
                spacing: Style.space(12)

                Item {
                    width: parent.width
                    height: Style.space(22)

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.t("workspaces")
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
                            onRightClicked: root.showHint(root.t("workspaces2"), root.t("displayTheFirstPage"), "")
                            Accessible.name: root.t("workspacesTo")
                        }

                        Ui.Button {
                            implicitHeight: Style.space(20)
                            implicitWidth: Style.space(40)
                            text: "5 – 8"
                            selected: root.workspacePage === 1
                            bordered: true
                            focusable: true
                            onClicked: root.workspacePage = 1
                            onRightClicked: root.showHint(root.t("workspaces3"), root.t("displayTheSecondPage"), "")
                            Accessible.name: root.t("workspacesTo2")
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
                    onRightClicked: root.showHint(root.t("allWorkspaces"), root.t("selectTheGlobalDefault"), root.t("tipSetTheDefault"))
                    Accessible.name: root.t("allWorkspacesDefault")
                    tooltipText: root.t("setTheDefaultWindow")

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    enabled: false

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.t("allWorkspaces")
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: allCard.selected
                        opacity: allCard.selected ? 1.0 : 0.85
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.t("defaultWindows", [root.cap])
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
                            var base = root.t("workspaceN", [modelData]) + (modelData === root.currentWsId ? root.t("active") : "")
                            if (wsCard.isManual) {
                                var summary = wsCard.hasSavedApps ? root.t("appsSaved", [wsCard.savedApps.length]) : root.t("appPreset")
                                if (root.workspaceAutostart(modelData)) summary += root.t("autostartOn")
                                return base + "\n" + summary
                            }
                            if (root.isWorkspaceNative(modelData)) return base + "\n" + root.t("nativeNoLimit")
                            var presetKey = root.autoPresetForWorkspace(modelData)
                            var presetDesc = presetKey === "none" ? root.t("nativeNoPreset") : (root.autoPresetLabel(presetKey) + (root.hasCustomPreset(modelData) ? root.t("custom") : root.t("default2")))
                            return base + "\n" + root.t("limitPreset", [root.capForWorkspace(modelData), presetDesc])
                        }
                        onClicked: root.selectedWorkspace = modelData
                        onRightClicked: root.showHint(root.t("wsCardTitle", [wsCard.modelData]), wsCard.isManual ? root.t("wsCardManual", [wsCard.modelData, root.savedLayoutSummary(wsCard.modelData)]) : root.isWorkspaceNative(wsCard.modelData) ? root.t("wsCardNative", [wsCard.modelData]) : root.t("wsCardPresets", [wsCard.modelData, root.capForWorkspace(wsCard.modelData), root.autoPresetLabel(root.autoPresetForWorkspace(wsCard.modelData))]), root.t("tipLeftClickTo2"))
                        Accessible.name: root.t("workspaceN", [modelData])

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
                                    text: wsCard.isManual ? root.t("appPreset") : (root.isWorkspaceNative(wsCard.modelData) ? root.t("noLimit") : root.t("maxN", [root.capForWorkspace(wsCard.modelData)]))
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
                                    border.color: "#2c2d38"
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
                                        text: root.t("noAppPreset")
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
                                            border.color: "#686873"
                                            opacity: 1.0
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.t("native")
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
                        text: root.t("workspaceN", [root.selectedWorkspace]).toUpperCase() + (root.selectedWorkspace === root.currentWsId ? root.t("active2") : "")
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
                            text: root.t("presets")
                            selected: root.activeWorkspaceTab === "presets"
                            bordered: true
                            focusable: true
                            onClicked: root.setWorkspaceMode(root.selectedWorkspace, "auto")
                            onRightClicked: root.showHint(root.t("presetsMode"), root.t("dynamicAutomaticTilingNewly"), root.t("tipSelectFromGeometric"))
                            tooltipText: root.t("presetsGeometricTilingLayout")
                        }
                        Ui.Button {
                            width: (parent.width - Style.space(6)) / 2
                            text: root.t("appPresets")
                            selected: root.activeWorkspaceTab === "manual"
                            bordered: true
                            focusable: true
                            onClicked: root.setWorkspaceMode(root.selectedWorkspace, "manual")
                            onRightClicked: root.showHint(root.t("appPresetsMode"), root.t("switchesThisWorkspaceTo"), root.t("tipSaveCapturesYour"))
                            tooltipText: root.t("appPresetsEditWindows")
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
                            text: root.t("resetWsTo", [root.selectedWorkspace, root.cap])
                            bordered: true
                            focusable: true
                            fontSize: Style.font.caption
                            onClicked: root.resetWorkspaceCap(root.selectedWorkspace)
                            onRightClicked: root.showHint(root.t("resetLimitToDefault"), root.t("resetLimitBody", [root.selectedWorkspace, root.cap]), "")
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
                                    onRightClicked: root.showHint(root.t("windowLimitN", [index + 1]), root.t("windowLimitBody", [root.selectedWorkspace]), root.t("tipWindowsIsRecommended"))
                                    Accessible.name: root.tn("windowsN", index + 1)
                                }
                            }
                        }

                        Text {
                            text: root.t("layoutPreset")
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
                                visible: root.hasCustomPreset(root.selectedWorkspace) || root.hasCustomCap(root.selectedWorkspace) || root.isWorkspaceNative(root.selectedWorkspace)
                                width: (parent.width - Style.space(6)) / 2
                                text: root.t("resetToDefault")
                                bordered: true
                                focusable: true
                                fontSize: Style.font.caption
                                onClicked: root.resetWorkspaceToDefault(root.selectedWorkspace)
                                onRightClicked: root.showHint(root.t("resetWorkspaceToDefault"), root.t("resetWsBody", [root.selectedWorkspace, root.cap]), "")
                                tooltipText: root.t("resetTip", [root.cap, root.autoPresetLabel(root.defaultAutoPresetFor(root.cap))])
                            }

                            Ui.Button {
                                width: (root.hasCustomPreset(root.selectedWorkspace) || root.hasCustomCap(root.selectedWorkspace) || root.isWorkspaceNative(root.selectedWorkspace)) ? ((parent.width - Style.space(6)) / 2) : parent.width
                                text: root.autoPresetForWorkspace(root.selectedWorkspace) === "none" ? root.t("nativeNoPreset2") : root.t("removePresetNative")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "none"
                                bordered: true
                                focusable: true
                                fontSize: Style.font.caption
                                onClicked: root.setWorkspaceAutoPreset(root.selectedWorkspace, "none")
                                onRightClicked: root.showHint(root.t("nativeLayoutNoPreset"), root.t("usesNativeHyprlandTiling"), "")
                                tooltipText: root.t("removePresetTip", [root.selectedWorkspace])
                            }
                        }

                        // Inline Banner if App Preset exists on this workspace
                        Rectangle {
                            visible: root.hasSavedLayout(root.selectedWorkspace)
                            width: parent.width
                            implicitHeight: appPresetBannerRow.implicitHeight + Style.space(8)
                            radius: Style.space(4)
                            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                            border.width: 1
                            border.color: Color.accent

                            Row {
                                id: appPresetBannerRow
                                width: parent.width - Style.space(12)
                                anchors.centerIn: parent
                                spacing: Style.space(6)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - removeAppPresetBtn.width - Style.space(6)
                                    text: root.t("appPresetSaved", [root.savedAppsFor(root.selectedWorkspace).length])
                                    color: Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Ui.Button {
                                    id: removeAppPresetBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.t("removeAppPreset")
                                    bordered: true
                                    focusable: true
                                    fontSize: Math.max(9, Style.font.caption - 1)
                                    onClicked: root.clearWorkspaceLayout(root.selectedWorkspace)
                                    tooltipText: root.t("removeSavedTip", [root.selectedWorkspace])
                                }
                            }
                        }

                        // A single tiled window fills the workspace; subsequent windows overflow.
                        Ui.Button {
                            visible: root.effectiveCapFor(root.selectedWorkspace) === 1
                            width: parent.width
                            text: root.t("oneWindowTiling")
                            selected: !root.isWorkspaceNative(root.selectedWorkspace)
                            bordered: true
                            focusable: true
                            onClicked: root.setWorkspaceAutoPreset(root.selectedWorkspace, "side-by-side")
                            onRightClicked: root.showHint(root.t("oneWindowTiling2"), root.t("keepsOneTiledWindow"), root.t("tipSelectNativeTo"))
                            tooltipText: root.t("applyOneWindowTiling")
                            Accessible.name: root.t("oneWindowTiling3")
                        }

                        // Presets for Cap = 2
                        Row {
                            visible: root.effectiveCapFor(root.selectedWorkspace) === 2
                            width: parent.width
                            spacing: Style.space(6)
                            Ui.Button {
                                width: (parent.width - Style.space(6)) / 2
                                text: root.t("sideBySide2")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "side-by-side"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "side-by-side")
                                onRightClicked: root.showHint(root.t("sideBySidePreset"), root.t("arrangesWindowsIntoTwo"), root.t("tipClickAgainTo"))
                                tooltipText: root.t("sideBySideColumns")
                            }
                            Ui.Button {
                                width: (parent.width - Style.space(6)) / 2
                                text: root.t("stacked2")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "stacked"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "stacked")
                                onRightClicked: root.showHint(root.t("stackedPreset"), root.t("arrangesWindowsIntoTwo2"), root.t("tipGreatForVertical"))
                                tooltipText: root.t("verticallyStackedRowsTop")
                            }
                        }

                        // Presets for Cap = 3
                        Row {
                            visible: root.effectiveCapFor(root.selectedWorkspace) === 3
                            width: parent.width
                            spacing: Style.space(6)
                            Ui.Button {
                                width: (parent.width - 2 * Style.space(6)) / 3
                                text: root.t("masterL")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-left"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-left")
                                onRightClicked: root.showHint(root.t("masterLeftPreset"), root.t("positionsLargeMasterWindow"), root.t("tipPerfectForEditor"))
                                tooltipText: root.t("masterOnLeftStacked")
                            }
                            Ui.Button {
                                width: (parent.width - 2 * Style.space(6)) / 3
                                text: root.t("masterR")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-right"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-right")
                                onRightClicked: root.showHint(root.t("masterRightPreset"), root.t("positionsLargeMasterWindow2"), "")
                                tooltipText: root.t("stackedOnLeftMaster")
                            }
                            Ui.Button {
                                width: (parent.width - 2 * Style.space(6)) / 3
                                text: root.t("columns2")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "columns"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "columns")
                                onRightClicked: root.showHint(root.t("columnsPreset"), root.t("dividesTheWorkspaceInto"), root.t("tipIdealForMulti"))
                                tooltipText: root.t("columnsSideBySide")
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
                                text: root.t("grid2")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "grid"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "grid")
                                onRightClicked: root.showHint(root.t("gridPreset"), root.t("arrangesWindowsIntoA"), "")
                                tooltipText: root.t("gridArrangementClickAgain")
                            }
                            Ui.Button {
                                width: (content.width - Style.space(6)) / 2
                                text: root.t("masterL")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-left"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-left")
                                onRightClicked: root.showHint(root.t("masterLeftPreset"), root.t("largeMasterWindowOn"), "")
                                tooltipText: root.t("masterOnLeftStacked2")
                            }
                            Ui.Button {
                                width: (content.width - Style.space(6)) / 2
                                text: root.t("masterR")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "master-right"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "master-right")
                                onRightClicked: root.showHint(root.t("masterRightPreset"), root.t("largeMasterWindowOn2"), "")
                                tooltipText: root.t("stackedOnLeftMaster2")
                            }
                            Ui.Button {
                                width: (content.width - Style.space(6)) / 2
                                text: root.t("columns3")
                                selected: root.autoPresetForWorkspace(root.selectedWorkspace) === "columns"
                                bordered: true
                                focusable: true
                                onClicked: root.toggleWorkspaceAutoPreset(root.selectedWorkspace, "columns")
                                onRightClicked: root.showHint(root.t("columnsPreset2"), root.t("dividesTheWorkspaceInto2"), "")
                                tooltipText: root.t("columnsSideBySide2")
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
                                        ? root.t("appPresetSummary", [root.savedLayoutSummary(root.selectedWorkspace)])
                                        : root.t("noAppPresetSaved")
                                    color: Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    text: root.t("removesAnAppFrom")
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
                                                    textFormat: Text.PlainText
                                                    text: chipRect.modelData.name || chipRect.modelData.class || root.t("app")
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
                                                        text: root.t("removeFromLayout", [chipRect.modelData.name || chipRect.modelData.class || root.t("appLower")])
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
                                    textFormat: Text.PlainText
                                    text: root.t("lastRestoreFailed", [failureText])
                                    color: Color.urgent
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }

                                Text {
                                    visible: !root.hasSavedLayout(root.selectedWorkspace)
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: root.t("openArrange", [root.selectedWorkspace])
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
                                        text: root.t("existingWindows", [root.restoreConflict ? root.restoreConflict.workspace : ""])
                                        color: Color.urgent
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: root.t("wsHasConflicts", [root.restoreConflict ? root.restoreConflict.conflict_count : 0])
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
                                                textFormat: Text.PlainText
                                                text: modelData.title ? (modelData.class + " (" + modelData.title + ")") : (modelData.class || root.t("window2"))
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
                                    text: root.t("howWouldYouLike")
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
                                            text: root.t("moveToWs", [root.restoreConflict ? root.restoreConflict.next_free_workspace : ""])
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: root.restoreWorkspaceApps(root.selectedWorkspace, "move")
                                            onRightClicked: root.showHint(root.t("moveConflictingWindows"), root.t("moveBody", [root.selectedWorkspace, root.restoreConflict ? root.restoreConflict.next_free_workspace : ""]), "")
                                            tooltipText: root.t("moveConflictingWindowsTo")
                                        }
                                        Ui.Button {
                                            width: (parent.width - Style.space(6)) / 2
                                            text: root.t("close")
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: root.restoreWorkspaceApps(root.selectedWorkspace, "close")
                                            onRightClicked: root.showHint(root.t("closeConflictingWindows"), root.t("closeBody", [root.selectedWorkspace]), "")
                                            tooltipText: root.t("closeExistingWindowsAnd")
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Style.space(6)
                                        Ui.Button {
                                            width: (parent.width - Style.space(6)) / 2
                                            text: root.t("keepFloat")
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: root.restoreWorkspaceApps(root.selectedWorkspace, "keep")
                                            onRightClicked: root.showHint(root.t("keepConflictingWindows"), root.t("keepBody", [root.selectedWorkspace]), "")
                                            tooltipText: root.t("keepExistingWindowsOn")
                                        }
                                        Ui.Button {
                                            width: (parent.width - Style.space(6)) / 2
                                            text: root.t("cancel")
                                            bordered: true
                                            focusable: true
                                            fontSize: Style.font.caption
                                            onClicked: {
                                                root.restoreConflict = null
                                                root.lastMessage = root.t("restoreCancelled")
                                            }
                                            onRightClicked: root.showHint(root.t("cancelRestore"), root.t("abortsRestoringTheApp"), "")
                                            tooltipText: root.t("cancelRestoringThisPreset")
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
                                text: root.t("saveAppPreset")
                                bordered: true
                                focusable: true
                                onClicked: root.captureWorkspaceLayout(root.selectedWorkspace)
                                onRightClicked: root.showHint(root.t("saveAppPreset"), root.t("saveBody", [root.selectedWorkspace]), root.t("tipOpenAndArrange"))
                                tooltipText: root.t("saveTip", [root.selectedWorkspace])
                            }

                            Ui.Button {
                                visible: root.hasSavedLayout(root.selectedWorkspace) && root.savedAppsFor(root.selectedWorkspace).length > 0
                                width: (parent.width - Style.space(6)) / 2
                                text: root.t("restoreAppPreset")
                                bordered: true
                                focusable: true
                                onClicked: root.restoreWorkspaceApps(root.selectedWorkspace)
                                onRightClicked: root.showHint(root.t("restoreAppPreset"), root.t("relaunchesMissingAppsAnd"), root.t("tipEnableAutoMove"))
                                tooltipText: root.t("restoreTip", [root.selectedWorkspace])
                            }
                        }

                        Ui.Button {
                            visible: root.hasSavedLayout(root.selectedWorkspace)
                            width: parent.width
                            text: root.t("removeAppPreset")
                            bordered: true
                            focusable: true
                            fontSize: Style.font.caption
                            onClicked: root.clearWorkspaceLayout(root.selectedWorkspace)
                            onRightClicked: root.showHint(root.t("removeAppPreset2"), root.t("removeBody", [root.selectedWorkspace]), "")
                            tooltipText: root.t("removeTip", [root.selectedWorkspace])
                        }

                        // Toggles
                        Ui.Toggle {
                            width: parent.width
                            label: root.t("saveAppsShowIcons")
                            description: root.t("displayAppIconsIn")
                            checked: root.workspaceSaveApps(root.selectedWorkspace)
                            onClicked: root.toggleWorkspaceSaveApps(root.selectedWorkspace)

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: root.showHint(root.t("saveAppsShowIcons2"), root.t("savesTheApplicationDesktop"), "")
                            }
                        }

                        Ui.Toggle {
                            width: parent.width
                            label: root.t("autostartOnSessionStartup")
                            description: root.t("automaticallyLaunchSavedApps")
                            checked: root.workspaceAutostart(root.selectedWorkspace)
                            onClicked: root.toggleWorkspaceAutostart(root.selectedWorkspace)

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: root.showHint(root.t("autostartOnStartup"), root.t("automaticallyLaunchesThisWor"), root.t("tipSetThisOn"))
                            }
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
                    text: root.t("defaultWindowLimitAll")
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
                            onRightClicked: root.showHint(root.t("globalLimitN", [index + 1]), root.t("globalLimitBody", [index + 1]), "")
                            Accessible.name: root.tn("windowsN", index + 1)
                        }
                    }
                }

                Text {
                    visible: root.cap > 1
                    text: root.t("defaultLayoutPreset")
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
                        text: root.t("sideBySide2")
                        selected: (root.defaultAutoPresets["2"] || "side-by-side") === "side-by-side"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("2", "side-by-side")
                        onRightClicked: root.showHint(root.t("defaultPresetSideBy"), root.t("setsSideBySide"), "")
                        tooltipText: root.t("defaultToSideBy")
                    }
                    Ui.Button {
                        width: (parent.width - Style.space(6)) / 2
                        text: root.t("stacked2")
                        selected: root.defaultAutoPresets["2"] === "stacked"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("2", "stacked")
                        onRightClicked: root.showHint(root.t("defaultPresetStacked"), root.t("setsStackedRowsAs"), "")
                        tooltipText: root.t("defaultToVerticallyStacked")
                    }
                }

                // Default Preset choices for Cap = 3
                Row {
                    visible: root.cap === 3
                    width: parent.width
                    spacing: Style.space(6)
                    Ui.Button {
                        width: (parent.width - Style.space(12)) / 3
                        text: root.t("masterL")
                        selected: (root.defaultAutoPresets["3"] || "master-left") === "master-left"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("3", "master-left")
                        onRightClicked: root.showHint(root.t("defaultPresetMasterLeft"), root.t("setsMasterOnLeft"), "")
                        tooltipText: root.t("defaultToMasterOn")
                    }
                    Ui.Button {
                        width: (parent.width - Style.space(12)) / 3
                        text: root.t("masterR")
                        selected: root.defaultAutoPresets["3"] === "master-right"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("3", "master-right")
                        onRightClicked: root.showHint(root.t("defaultPresetMasterRight"), root.t("setsMasterOnRight"), "")
                        tooltipText: root.t("defaultToStackedOn")
                    }
                    Ui.Button {
                        width: (parent.width - Style.space(12)) / 3
                        text: root.t("columns2")
                        selected: root.defaultAutoPresets["3"] === "columns"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("3", "columns")
                        onRightClicked: root.showHint(root.t("defaultPresetColumns"), root.t("setsEqualSideBy"), "")
                        tooltipText: root.t("defaultToColumnsSide")
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
                        text: root.t("grid2")
                        selected: (root.defaultAutoPresets["4"] || "grid") === "grid"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "grid")
                        onRightClicked: root.showHint(root.t("defaultPresetGrid"), root.t("setsFourQuadrantGrid"), "")
                        tooltipText: root.t("defaultToGrid")
                    }
                    Ui.Button {
                        width: (content.width - Style.space(6)) / 2
                        text: root.t("masterL")
                        selected: root.defaultAutoPresets["4"] === "master-left"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "master-left")
                        onRightClicked: root.showHint(root.t("defaultPresetMasterLeft"), root.t("setsMasterOnLeft2"), "")
                        tooltipText: root.t("defaultToMasterOn2")
                    }
                    Ui.Button {
                        width: (content.width - Style.space(6)) / 2
                        text: root.t("masterR")
                        selected: root.defaultAutoPresets["4"] === "master-right"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "master-right")
                        onRightClicked: root.showHint(root.t("defaultPresetMasterRight"), root.t("setsMasterOnRight2"), "")
                        tooltipText: root.t("defaultToMasterOn3")
                    }
                    Ui.Button {
                        width: (content.width - Style.space(6)) / 2
                        text: root.t("columns3")
                        selected: root.defaultAutoPresets["4"] === "columns"
                        bordered: true
                        focusable: true
                        onClicked: root.setDefaultAutoPreset("4", "columns")
                        onRightClicked: root.showHint(root.t("defaultPresetColumns"), root.t("setsEqualSideBy2"), "")
                        tooltipText: root.t("defaultToColumnsSide2")
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Color.foreground
                    opacity: 0.12
                }

                Text {
                    text: root.t("presetAppPresetManagement")
                    color: Color.foreground
                    opacity: 0.65
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                }

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Ui.Button {
                        width: (parent.width - Style.space(6)) / 2
                        text: root.t("removeAllPresets")
                        bordered: true
                        focusable: true
                        fontSize: Style.font.caption
                        onClicked: root.removeAllWorkspacePresets()
                        onRightClicked: root.showHint(root.t("removeAllPresets2"), root.t("setsAllWorkspacesTo"), "")
                        tooltipText: root.t("setAllWorkspacesTo")
                    }

                    Ui.Button {
                        width: (parent.width - Style.space(6)) / 2
                        text: root.t("resetAllToDefault")
                        bordered: true
                        focusable: true
                        fontSize: Style.font.caption
                        onClicked: root.resetAllWorkspacesToDefault()
                        onRightClicked: root.showHint(root.t("resetAllWorkspaces"), root.t("resetAllBody", [root.cap, root.autoPresetLabel(root.defaultAutoPresetFor(root.cap))]), "")
                        tooltipText: root.t("resetAllWorkspacesTo")
                    }
                }

                Ui.Button {
                    visible: root.hasAnyAppPreset
                    width: parent.width
                    text: root.t("removeAllAppPresets")
                    bordered: true
                    focusable: true
                    fontSize: Style.font.caption
                    onClicked: root.removeAllAppPresets()
                    onRightClicked: root.showHint(root.t("removeAllAppPresets2"), root.t("deletesAllSavedApp"), "")
                    tooltipText: root.t("deleteAllSavedApp")
                }
            }

            Ui.Button {
                width: parent.width
                text: root.t("clearAllPresetsApp")
                bordered: true
                focusable: true
                onClicked: root.clearAllPresets()
                tooltipText: root.t("clearAllWorkspaceLayouts")
            }

            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.failed ? root.lastMessage : (root.tilingActive ? root.lastMessage : root.t("yourWindowsStayWhere"))
                wrapMode: Text.Wrap
                color: root.failed ? Color.urgent : Color.foreground
                opacity: root.failed ? 1 : 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
            } // end workspaceControlsView

        }
        }
    }
}
