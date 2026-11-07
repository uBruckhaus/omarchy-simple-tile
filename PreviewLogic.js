.pragma library

// The workspace preview's rules: what a drag, a click or a key in the large
// preview changes in this widget's settings entry (the same entry Theme
// Manager edits while this plugin is on the bar). A port of Theme Manager's
// workspace_state.py, kept free of QML so node can test it.
//
// Every change works on a COPY of the entry (copy(entry)) and returns what the
// desktop needs afterwards: ["apply", ws, preset], ["remove", ws] or null.

var FREE = ["floating", "scrolling"]
var TILING_BY_CAP = {
    "2": ["side-by-side", "stacked"],
    "3": ["columns", "master-left", "master-right"],
    "4": ["columns", "master-left", "master-right", "grid"]
}
var BUILTIN_DEFAULT = { "2": "side-by-side", "3": "master-left", "4": "grid" }
var SPLIT_PRESETS = ["master-left", "master-right", "side-by-side", "stacked", "columns"]
var SPLIT_MIN = 0.2
var SPLIT_MAX = 0.8
var COLUMNS_SPLIT_MAX = 0.6
var MIN_SHARE = 0.1
var GAP = 0.035
var SAVED_INSET = 0.04
var MAX_SAVED_WINDOWS = 8

function copy(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value))
}

function _map(entry, key) {
    var value = entry[key]
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        value = {}
        entry[key] = value
    }
    return value
}

function _isInt(v) { return typeof v === "number" && Math.floor(v) === v }
function _has(list, v) { return list.indexOf(v) >= 0 }
function _tiling(cap) { return TILING_BY_CAP[String(cap)] || [] }

// --- reading -------------------------------------------------------------------------------

function globalCap(entry) {
    var cap = entry.maxWindows
    return _isInt(cap) && cap >= 1 && cap <= 4 ? cap : 2
}

function hasCustomCap(entry, ws) {
    var v = (entry.workspaceCaps || {})[String(ws)]
    return _isInt(v) && v >= 1 && v <= 4
}

function layoutFor(entry, ws) { return (entry.workspaceLayouts || {})[String(ws)] || null }

function isManual(entry, ws) {
    var mode = (entry.workspaceModes || {})[String(ws)]
    if (mode === "manual" || mode === "auto") return mode === "manual"
    var layout = layoutFor(entry, ws)
    return Boolean(layout && layout.mode === "manual")
}

var MAX_SAVED = 16      // as the helper: no more saved windows are ever read (shell.json can be edited)

function savedWindows(entry, ws) {
    var layout = layoutFor(entry, ws)
    return layout && Array.isArray(layout.windows)
        ? layout.windows.slice(0, MAX_SAVED).filter(function(w) { return w && typeof w === "object" && !Array.isArray(w) })
        : []
}

function effectiveCap(entry, ws) {
    if (ws <= 0) return globalCap(entry)
    if (hasCustomCap(entry, ws)) return entry.workspaceCaps[String(ws)]
    if (isManual(entry, ws)) {
        var count = savedWindows(entry, ws).length
        if (count >= 1 && count <= 4) return count
    }
    return globalCap(entry)
}

function defaultPresetFor(entry, cap) {
    var saved = (entry.defaultAutoPresets || {})[String(cap)]
    return saved || BUILTIN_DEFAULT[String(cap)] || "side-by-side"
}

function ownPreset(entry, ws) {
    var v = (entry.workspaceAutoPresets || {})[String(ws)]
    return v === undefined ? null : v
}

function omarchyFreeMode(modes, ws) {
    var mode = (modes || {})[String(ws)]
    return _has(FREE, mode) ? mode : ""
}

function presetFor(entry, ws, modes) {
    if (isManual(entry, ws)) return ""
    var own = ownPreset(entry, ws)
    if (own && own !== "none") return own
    if (omarchyFreeMode(modes, ws)) return omarchyFreeMode(modes, ws)
    if (own) return own
    return defaultPresetFor(entry, effectiveCap(entry, ws))
}

function shownPreset(entry, ws, modes) {
    return ws <= 0 ? defaultPresetFor(entry, globalCap(entry)) : presetFor(entry, ws, modes)
}

function isNative(entry, ws, modes) { return ws > 0 && presetFor(entry, ws, modes) === "none" }
function isFree(entry, ws, modes) { return _has(FREE, presetFor(entry, ws, modes)) }

function presetForCap(entry, ws, cap) {
    // The layout a workspace would have with another window limit.
    var own = ws > 0 ? ownPreset(entry, ws) : null
    if (own && _has(_tiling(cap), own)) return own
    return cap > 1 ? defaultPresetFor(entry, cap) : "side-by-side"
}

// --- changing (on a copy) --------------------------------------------------------------------

function _toAuto(entry, ws, keepCap) {
    if (isManual(entry, ws)) {
        if (keepCap && !hasCustomCap(entry, ws)) _map(entry, "workspaceCaps")[String(ws)] = effectiveCap(entry, ws)
        _map(entry, "workspaceModes")[String(ws)] = "auto"
        return true
    }
    return false
}

function setGlobalCap(entry, cap) {
    if (_isInt(cap) && cap >= 1 && cap <= 4) entry.maxWindows = cap
    return null
}

function setDefaultPreset(entry, cap, preset) {
    _map(entry, "defaultAutoPresets")[String(cap)] = preset
    return null
}

function setCap(entry, ws, cap, modes) {
    var wasNative = isNative(entry, ws, modes) || isFree(entry, ws, modes)
    var wasFree = Boolean(omarchyFreeMode(modes, ws)) && !isManual(entry, ws)
    var wasManual = _toAuto(entry, ws, false)
    _map(entry, "workspaceCaps")[String(ws)] = cap
    if (wasNative) _map(entry, "workspaceAutoPresets")[String(ws)] = defaultPresetFor(entry, cap)
    if (wasFree) return ["apply", ws, defaultPresetFor(entry, cap)]
    if (wasManual || wasNative) {
        var preset = presetFor(entry, ws, modes) || defaultPresetFor(entry, cap)
        if (preset && preset !== "none" && cap > 1) return ["apply", ws, preset]
    }
    return null
}

function setPreset(entry, ws, preset) {
    _map(entry, "workspaceAutoPresets")[String(ws)] = preset
    _toAuto(entry, ws, true)
    return preset === "none" ? ["remove", ws] : ["apply", ws, preset]
}

// --- split ratio ---------------------------------------------------------------------------------

function splitRange(preset) {
    return preset === "columns" ? [SPLIT_MIN, COLUMNS_SPLIT_MAX] : [SPLIT_MIN, SPLIT_MAX]
}

function hasDivider(preset, cap) {
    if (preset === "columns") return cap === 3
    return _has(SPLIT_PRESETS, preset) && cap >= 2
}

function splitFor(entry, ws) {
    var own = ws > 0 ? (entry.workspaceSplits || {})[String(ws)] : undefined
    var value = own !== undefined ? own : entry.defaultSplit
    return typeof value === "number" && value >= SPLIT_MIN && value <= SPLIT_MAX ? value : null
}

function setSplit(entry, ws, value, modes) {
    if (value !== null && value !== undefined) {
        var range = splitRange(ws > 0 ? presetFor(entry, ws, modes) : defaultPresetFor(entry, globalCap(entry)))
        value = Math.round(Math.min(range[1], Math.max(range[0], Number(value))) * 100) / 100
    } else {
        value = null
    }
    if (ws <= 0) {
        if (value === null) delete entry.defaultSplit
        else entry.defaultSplit = value
        return null
    }
    if (value === null) delete _map(entry, "workspaceSplits")[String(ws)]
    else _map(entry, "workspaceSplits")[String(ws)] = value
    var preset = presetFor(entry, ws, modes)
    return _has(SPLIT_PRESETS, preset) && !isManual(entry, ws) ? ["apply", ws, preset] : null
}

// --- adding a window -------------------------------------------------------------------------------

function addZonePreset(cap, u, v) {
    // The layout a "+" dropped at (u, v) of the windows' area asks for. It only
    // chooses the layout for the new limit; Hyprland still decides where the
    // next window opens.
    u = Math.min(1, Math.max(0, u))
    v = Math.min(1, Math.max(0, v))
    if (cap <= 1) return null
    if (cap === 2) return Math.min(v, 1 - v) < Math.min(u, 1 - u) ? "stacked" : "side-by-side"
    var side = u < 0.3 || u > 0.7
    if (cap >= 4 && side && (v < 0.3 || v > 0.7)) return "grid"
    if (u < 0.3) return "master-left"
    if (u > 0.7) return "master-right"
    return "columns"
}

function tilesFreely(entry, ws, modes) {
    return ws > 0 && !isManual(entry, ws) && (isNative(entry, ws, modes) || isFree(entry, ws, modes))
}

function addedCap(entry, ws, modes) {
    // One more window, or on Native/Floating/Scrolling: "Tile with 2 windows".
    if (ws > 0 && isManual(entry, ws)) return null
    var cap = ws <= 0 ? globalCap(entry) : effectiveCap(entry, ws)
    if (tilesFreely(entry, ws, modes)) return 2
    return cap < 4 ? cap + 1 : null
}

function canAddWindow(entry, ws, modes) { return addedCap(entry, ws, modes) !== null }

function addWindow(entry, ws, preset, modes) {
    var cap = addedCap(entry, ws, modes)
    if (cap === null) return null
    if (preset && !_has(_tiling(cap), preset)) preset = null
    if (ws <= 0) {
        setGlobalCap(entry, cap)
        if (preset) setDefaultPreset(entry, cap, preset)
        return null
    }
    var own = ownPreset(entry, ws)
    var action = setCap(entry, ws, cap, modes)
    if (preset) return setPreset(entry, ws, preset)
    if (own && own !== "none" && !_has(FREE, own) && !_has(_tiling(cap), own))
        return setPreset(entry, ws, defaultPresetFor(entry, cap))   // no version for the new limit
    return action
}

function resetCap(entry, ws, modes) {
    var wasManual = _toAuto(entry, ws, false)
    delete _map(entry, "workspaceCaps")[String(ws)]
    if (wasManual) {
        var preset = presetFor(entry, ws, modes) || defaultPresetFor(entry, globalCap(entry))
        if (preset && preset !== "none" && globalCap(entry) > 1) return ["apply", ws, preset]
    }
    return null
}

function removedCap(entry, ws, modes) {
    // The limit "−" gives: one fewer; with one window left the default limit
    // again (a workspace's own limit dropped; All Workspaces back to 2).
    // null where − does nothing (an App Preset, Native/Floating/Scrolling).
    if (ws > 0 && (isManual(entry, ws) || tilesFreely(entry, ws, modes))) return null
    if (ws <= 0) {
        var g = globalCap(entry)
        if (g > 1) return g - 1
        return entry.maxWindows !== undefined ? 2 : null
    }
    var cap = effectiveCap(entry, ws)
    if (cap > 1) return cap - 1
    return hasCustomCap(entry, ws) ? globalCap(entry) : null
}

function canRemoveWindow(entry, ws, modes) { return removedCap(entry, ws, modes) !== null }

function removeWindow(entry, ws, modes) {
    // "−" and the − key: one window fewer, or with one window the default limit.
    var next = removedCap(entry, ws, modes)
    if (next === null) return null
    if (ws <= 0) {
        if (globalCap(entry) > 1) return setGlobalCap(entry, next)
        delete entry.maxWindows
        return null
    }
    if (effectiveCap(entry, ws) > 1) return setCap(entry, ws, next, modes)
    var own = ownPreset(entry, ws)
    resetCap(entry, ws, modes)
    next = effectiveCap(entry, ws)
    if (own && own !== "none" && !_has(FREE, own) && !_has(_tiling(next), own))
        return setPreset(entry, ws, defaultPresetFor(entry, next))
    var preset = presetFor(entry, ws, modes)
    return preset && preset !== "none" && next > 1 ? ["apply", ws, preset] : null
}

function trayTargets(entry, ws, cap, modes) {
    // What a dragged window can be dropped on besides another window.
    if (cap <= 1) return []
    var current = shownPreset(entry, ws, modes)
    var order = ["master-left", "master-right", "columns", "grid", "side-by-side", "stacked"]
    var out = []
    for (var i = 0; i < order.length; i++)
        if (_has(_tiling(cap), order[i])) out.push({ preset: order[i], cap: cap, current: order[i] === current, fewer: false })
    out.push({ preset: presetForCap(entry, ws, cap - 1), cap: cap - 1, current: false, fewer: true })
    return out
}

function masterFlip(entry, ws, cap, index, x, width, modes) {
    if (cap < 3 || index === null || index === undefined) return null
    var preset = shownPreset(entry, ws, modes)
    if (preset === "master-left" && index === 0 && x > width / 2) return "master-right"
    if (preset === "master-right" && index === cap - 1 && x < width / 2) return "master-left"
    return null
}

// --- pictures --------------------------------------------------------------------------------------

function presetRects(preset, cap, split) {
    // Windows of a layout as [x, y, w, h] in 0…1. split: the master's share
    // (Master Left/Right), the left/top window's (Side-by-Side, Stacked) or the
    // middle column's (Columns with 3); null = even.
    var g = GAP
    var half = (1 - 3 * g) / 2
    var share = split === null || split === undefined ? 0.5 : split
    var first = (1 - 3 * g) * share
    var second = (1 - 3 * g) - first
    function column(x, w, n) {
        var h = (1 - (n + 1) * g) / n
        var out = []
        for (var i = 0; i < n; i++) out.push([x, g + i * (h + g), w, h])
        return out
    }
    var i
    if (cap <= 1 && !_has(["none", "floating", "scrolling"], preset)) return [[g, g, 1 - 2 * g, 1 - 2 * g]]
    if (preset === "side-by-side") return [[g, g, first, 1 - 2 * g], [2 * g + first, g, second, 1 - 2 * g]]
    if (preset === "stacked") return [[g, g, 1 - 2 * g, first], [g, 2 * g + first, 1 - 2 * g, second]]
    if (preset === "master-left" || preset === "master-right") {
        var rest = column(0, second, Math.max(1, cap - 1))
        var out = []
        if (preset === "master-left") {
            out.push([g, g, first, 1 - 2 * g])
            for (i = 0; i < rest.length; i++) out.push([2 * g + first, rest[i][1], rest[i][2], rest[i][3]])
            return out
        }
        for (i = 0; i < rest.length; i++) out.push([g, rest[i][1], rest[i][2], rest[i][3]])
        out.push([2 * g + second, g, first, 1 - 2 * g])
        return out
    }
    if (preset === "columns") {
        var n = Math.max(2, cap)
        if (n === 3 && split !== null && split !== undefined) {
            var part = 1 - 4 * g
            var mid = part * Math.min(split, COLUMNS_SPLIT_MAX)
            var side = (part - mid) / 2
            return [[g, g, side, 1 - 2 * g], [2 * g + side, g, mid, 1 - 2 * g], [3 * g + side + mid, g, side, 1 - 2 * g]]
        }
        var w = (1 - (n + 1) * g) / n
        var cols = []
        for (i = 0; i < n; i++) cols.push([g + i * (w + g), g, w, 1 - 2 * g])
        return cols
    }
    if (preset === "grid")
        return [[g, g, half, half], [2 * g + half, g, half, half], [g, 2 * g + half, half, half], [2 * g + half, 2 * g + half, half, half]]
    if (preset === "floating") return [[0.08, 0.12, 0.5, 0.5], [0.3, 0.28, 0.5, 0.5], [0.5, 0.08, 0.42, 0.42]]
    if (preset === "scrolling") return [[g, g, 0.42, 1 - 2 * g], [2 * g + 0.42, g, 0.42, 1 - 2 * g], [3 * g + 0.84, g, 0.42, 1 - 2 * g]]
    return [[g, g, half, 1 - 2 * g], [2 * g + half, g, half, half], [2 * g + half, 2 * g + half, half, half]]   // Native
}

function _geometry(window) {
    var at = window && window.at, size = window && window.size
    if (!Array.isArray(at) || !Array.isArray(size) || at.length !== 2 || size.length !== 2) return null
    for (var i = 0; i < 2; i++)
        if (typeof at[i] !== "number" || typeof size[i] !== "number" || !isFinite(at[i]) || !isFinite(size[i])) return null
    if (Math.min(size[0], size[1]) <= 0) return null
    return { at: at, size: size }
}

function savedBounds(windows) {
    var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, any = false
    for (var i = 0; i < windows.length; i++) {
        var g = _geometry(windows[i])
        if (!g) continue
        any = true
        x0 = Math.min(x0, g.at[0]); y0 = Math.min(y0, g.at[1])
        x1 = Math.max(x1, g.at[0] + g.size[0]); y1 = Math.max(y1, g.at[1] + g.size[1])
    }
    return any ? [x0, y0, Math.max(1, x1 - x0), Math.max(1, y1 - y0)] : null
}

function windowRects(windows, bounds) {
    // Saved windows (App Preset) scaled into 0…1 by their bounds (or by the
    // given ones, so a drag keeps the picture's scale).
    var b = bounds || savedBounds(windows)
    if (!b) return []
    var scale = 1 - 2 * SAVED_INSET
    var out = []
    for (var i = 0; i < windows.length; i++) {
        var g = _geometry(windows[i]) || { at: [b[0], b[1]], size: [800, 600] }
        out.push([SAVED_INSET + (g.at[0] - b[0]) / b[2] * scale, SAVED_INSET + (g.at[1] - b[1]) / b[3] * scale,
                  Math.max(0.02, g.size[0] / b[2] * scale - 0.015), Math.max(0.02, g.size[1] / b[3] * scale - 0.015)])
    }
    return out
}

// --- App Preset geometry -----------------------------------------------------------------------------

function savedCuts(windows, maxGap) {
    // Edges two tiled saved windows share: {axis, edge, start} (axis 0 = a
    // vertical line, 1 = a horizontal one; edge = where the first ends,
    // start = where the next begins).
    var bounds = savedBounds(windows)
    if (!bounds) return []
    var tiled = []
    for (var i = 0; i < windows.length; i++) {
        if (windows[i].floating) continue
        var g = _geometry(windows[i])
        if (g) tiled.push(g)
    }
    var seen = {}, cuts = []
    for (var axis = 0; axis < 2; axis++) {
        var other = 1 - axis
        var gap = maxGap !== undefined ? maxGap : Math.max(40, 0.03 * bounds[2 + axis])
        for (var a = 0; a < tiled.length; a++) {
            var end = tiled[a].at[axis] + tiled[a].size[axis]
            for (var b = 0; b < tiled.length; b++) {
                var d = tiled[b].at[axis] - end
                if (d < 0 || d > gap) continue
                var lo = Math.max(tiled[a].at[other], tiled[b].at[other])
                var hi = Math.min(tiled[a].at[other] + tiled[a].size[other], tiled[b].at[other] + tiled[b].size[other])
                if (hi <= lo) continue
                var key = axis + ":" + end + ":" + tiled[b].at[axis]
                if (seen[key]) continue
                seen[key] = true
                cuts.push({ axis: axis, edge: end, start: tiled[b].at[axis] })
            }
        }
    }
    cuts.sort(function(p, q) { return p.axis - q.axis || p.edge - q.edge || p.start - q.start })
    return cuts
}

function _overlap(a, b) {
    for (var i = 0; i < 2; i++)
        if (Math.min(a.at[i] + a.size[i], b.at[i] + b.size[i]) <= Math.max(a.at[i], b.at[i])) return false
    return true
}

function layoutTreeOk(windows) {
    // Can Restore rebuild these tiled windows as a split tree (simple_tile.py layout_tree)?
    var boxes = []
    for (var i = 0; i < windows.length; i++) {
        var g = _geometry(windows[i])
        if (!g) return false
        boxes.push(g)
    }
    function ok(list) {
        if (list.length <= 1) return true
        for (var axis = 0; axis < 2; axis++) {
            var ordered = list.slice().sort(function(p, q) { return p.at[axis] - q.at[axis] })
            for (var k = 1; k < ordered.length; k++) {
                var left = ordered.slice(0, k), right = ordered.slice(k)
                var edge = -Infinity, start = Infinity
                for (var l = 0; l < left.length; l++) edge = Math.max(edge, left[l].at[axis] + left[l].size[axis])
                for (var r = 0; r < right.length; r++) start = Math.min(start, right[r].at[axis])
                if (edge > start) continue
                return ok(left) && ok(right)
            }
        }
        return false
    }
    return ok(boxes)
}

function moveSavedCut(windows, axis, edge, start, middle) {
    // The shared edge moved so the gap's middle is at `middle` (px). Windows
    // ending at `edge` grow or shrink, those starting at `start` move along.
    // null if one would get too small, two would overlap, or Restore could
    // not rebuild it.
    var bounds = savedBounds(windows)
    if (!bounds) return null
    var delta = Math.round(middle - (edge + start) / 2)
    var least = MIN_SHARE * bounds[2 + axis]
    var out = []
    for (var i = 0; i < windows.length; i++) {
        var w = windows[i], g = _geometry(w)
        if (!g || w.floating) { out.push(w); continue }
        var at = g.at.slice(), size = g.size.slice()
        if (Math.abs(at[axis] + size[axis] - edge) <= 1) size[axis] += delta
        else if (Math.abs(at[axis] - start) <= 1) { at[axis] += delta; size[axis] -= delta }
        else { out.push(w); continue }
        if (size[axis] < least) return null
        out.push(Object.assign({}, w, { at: at, size: size }))
    }
    var tiled = []
    for (i = 0; i < out.length; i++) if (!out[i].floating && _geometry(out[i])) tiled.push(_geometry(out[i]))
    for (i = 0; i < tiled.length; i++)
        for (var j = i + 1; j < tiled.length; j++) if (_overlap(tiled[i], tiled[j])) return null
    var tiledWindows = out.filter(function(x) { return !x.floating })
    return layoutTreeOk(tiledWindows) ? out : null
}

function resizeSavedFloating(windows, index, width, height) {
    if (index < 0 || index >= windows.length || !windows[index].floating) return null
    var g = _geometry(windows[index]), bounds = savedBounds(windows)
    if (!g || !bounds) return null
    var out = windows.slice()
    out[index] = Object.assign({}, windows[index], {
        at: g.at.slice(),
        size: [Math.max(Math.round(width), Math.round(MIN_SHARE * bounds[2])),
               Math.max(Math.round(height), Math.round(MIN_SHARE * bounds[3]))]
    })
    return out
}

function setSavedWindows(entry, ws, windows) {
    var layout = layoutFor(entry, ws)
    if (!layout || !Array.isArray(windows)) return null
    entry.workspaceLayouts[String(ws)] = Object.assign({}, layout, { windows: windows, count: windows.length })
    return null
}

function swapSaved(entry, ws, first, second) {
    var layout = layoutFor(entry, ws)
    var windows = layout && Array.isArray(layout.windows) ? layout.windows.slice() : []
    if (first === second || first < 0 || second < 0 || first >= windows.length || second >= windows.length) return null
    var a = Object.assign({}, windows[first]), b = Object.assign({}, windows[second])
    a.at = windows[second].at; a.size = windows[second].size
    b.at = windows[first].at; b.size = windows[first].size
    windows[first] = a
    windows[second] = b
    entry.workspaceLayouts[String(ws)] = Object.assign({}, layout, { windows: windows })
    return null
}

function splitTarget(windows, index) {
    var tiled = []
    for (var i = 0; i < windows.length; i++) if (!windows[i].floating && _geometry(windows[i])) tiled.push(i)
    if (index !== null && index !== undefined && _has(tiled, index)) return index
    if (!tiled.length) return null
    var best = tiled[0]
    for (i = 1; i < tiled.length; i++) {
        var w = windows[tiled[i]], bw = windows[best]
        if (w.size[0] * w.size[1] > bw.size[0] * bw.size[1]) best = tiled[i]
    }
    return best
}

function addSavedApp(entry, ws, app, index, gap) {
    // A launcher joins the App Preset: the chosen (or largest) tiled window is
    // halved along its longer side, the app gets the second half. Saved only.
    var layout = layoutFor(entry, ws)
    if (!layout || !app || !(app.desktop_id || app.class)) return null
    gap = gap === undefined ? 10 : gap
    var windows = (layout.windows || []).map(function(w) { return Object.assign({}, w) })
    if (windows.length >= MAX_SAVED_WINDOWS) return null
    var windowClass = String(app.class || app.startup_class || app.desktop_id)
    var record = {}
    var keys = ["name", "icon", "desktop_id", "desktop_path"]
    for (var k = 0; k < keys.length; k++) if (app[keys[k]]) record[keys[k]] = String(app[keys[k]])
    record["class"] = windowClass
    var target = splitTarget(windows, index)
    var newAt, newSize
    if (target === null) {
        var b = savedBounds(windows) || [0, 0, 1920, 1080]
        newAt = [b[0], b[1]]; newSize = [b[2], b[3]]
    } else {
        var at = windows[target].at.slice(), size = windows[target].size.slice()
        var axis = size[0] >= size[1] ? 0 : 1
        var first = Math.floor((size[axis] - gap) / 2)
        if (first < 1) return null
        newAt = at.slice(); newSize = size.slice()
        newAt[axis] = at[axis] + first + gap
        newSize[axis] = size[axis] - first - gap
        size[axis] = first
        windows[target] = Object.assign({}, windows[target], { at: at, size: size })
    }
    windows.push({ "class": windowClass, at: newAt, size: newSize, floating: false, app: copy(record) })
    var apps = (layout.apps || []).slice()
    var id = record.desktop_id || record["class"]
    var listed = apps.some(function(a) { return (a.desktop_id || a["class"]) === id })
    if (!listed) apps.push(record)
    entry.workspaceLayouts[String(ws)] = Object.assign({}, layout, { apps: apps, windows: windows, count: windows.length })
    return null
}

// --- Undo of one change ----------------------------------------------------------------------------

function _same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
function _isMap(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

function undoMerge(current, before, after) {
    // Take back one change (before -> after) in `current`, keeping what
    // changed since (also in Theme Manager, which shares this entry): a key, or
    // one workspace's entry of a per-workspace map, goes back only if it is
    // still as the change left it. True if anything went back.
    var changed = false
    var keys = {}
    var k
    for (k in before) keys[k] = true
    for (k in after) keys[k] = true
    for (k in keys) {
        if (k === "id") continue
        var was = before[k], now = after[k], there = current[k]
        if (_same(was, now)) continue
        var wasMap = was === undefined && _isMap(now) ? {} : was
        var nowMap = now === undefined && _isMap(was) ? {} : now
        if (_isMap(wasMap) && _isMap(nowMap) && _isMap(there)) {
            var subs = {}
            var s
            for (s in wasMap) subs[s] = true
            for (s in nowMap) subs[s] = true
            for (s in subs) {
                if (!_same(wasMap[s], nowMap[s]) && _same(there[s], nowMap[s])) {
                    if (wasMap[s] === undefined) delete there[s]
                    else there[s] = copy(wasMap[s])
                    changed = true
                }
            }
            if (was === undefined && Object.keys(there).length === 0) delete current[k]
            continue
        }
        if (now === undefined && _isMap(was) && there === undefined) {
            current[k] = copy(was)
            changed = true
            continue
        }
        if (_same(there, now)) {
            if (was === undefined) delete current[k]
            else current[k] = copy(was)
            changed = true
        }
    }
    return changed
}
