import QtQuick
import "PreviewLogic.js" as Logic

// The chosen workspace drawn large, with the same drag and drop as Theme
// Manager's preview (port of its LookAlike + gestures). It changes nothing
// itself: it reports what the user asked for, with the workspace fixed when
// the gesture started, and BarWidget makes the change (and offers Undo).
//
//   drag a window onto a layout in the row at the bottom = that layout,
//   onto "− 1 window" or out of the preview = one window fewer,
//   the master window over the others = Master Left <-> Right,
//   one saved window of an App Preset onto another = they swap places,
//   the line between windows = their sizes (double-click: even),
//   the gap at the right edge = the window limit,
//   + = one window more (dragged in: where it lands picks the layout).
Item {
    id: preview

    // --- what to show (set by BarWidget) ---------------------------------------------
    property int ws: 0
    property int cap: 2
    property string preset: ""
    property var split: null
    property bool manual: false
    property bool dashed: false
    property var rects: []
    property bool plusVisible: false
    property bool minusVisible: false       // − at the left edge: one fewer / the default limit
    property int addCap: 0                  // the limit + gives (0: none)
    property bool tilesFreely: false
    property var trayTargets: []            // [{preset, cap, current, fewer}]
    property color fg: "#cdd6f4"
    property color bg: "#1e1e2e"
    property color accent: "#89b4fa"
    property string allLabel: ""            // All Workspaces: the defaults, drawn as a template
    property var t: function(key, args) { return key }
    property var presetLabel: function(p) { return p }
    property var presetForCap: function(cap) { return "side-by-side" }
    // Corners (the panel's Corners setting, qml/corners.js sizes): the preview is a card
    // (radius), its windows and tray slots swatches (small), its badge and tag pills (pill).
    property real radius: 8
    property real small: 4
    property real pill: 999

    signal addRequested(int ws, string preset)        // "" = a click: the layout it follows
    signal removeRequested(int ws)                    // − : one fewer, or the default limit
    signal splitRequested(int ws, var value)          // null = even
    signal capRequested(int ws, int cap)
    signal presetRequested(int ws, string preset)
    signal savedSwapRequested(int ws, int first, int second)

    // --- transient (drag) state ------------------------------------------------------
    property var shownRects: rects
    property bool shownDashed: dashed
    property string badge: ""
    property var highlight: null
    property var source: null
    property bool drop: false
    property bool edgeHover: false
    property bool edgeLit: false
    property bool plusHot: false
    property bool minusHot: false
    property var plusAt: null
    property string splitHover: ""
    property string splitLine: ""
    property var tray: []
    property var trayHot: null
    property var drag: null

    readonly property real edgeShare: 0.92
    readonly property real trayShare: 0.18

    implicitHeight: Math.round(width * 9 / 16)
    activeFocusOnTab: true

    onRectsChanged: if (!drag) { shownRects = rects; shownDashed = dashed; canvas.requestPaint() }
    onDashedChanged: if (!drag) { shownDashed = dashed; canvas.requestPaint() }
    onWsChanged: cancelDrag()
    onPlusVisibleChanged: canvas.requestPaint()
    onMinusVisibleChanged: canvas.requestPaint()
    onFgChanged: canvas.requestPaint()
    onBgChanged: canvas.requestPaint()
    onAccentChanged: canvas.requestPaint()
    onAllLabelChanged: canvas.requestPaint()
    onRadiusChanged: canvas.requestPaint()
    onSmallChanged: canvas.requestPaint()
    onPillChanged: canvas.requestPaint()
    onShownRectsChanged: if (highlight !== null && highlight >= shownRects.length) highlight = shownRects.length ? shownRects.length - 1 : null
    onActiveFocusChanged: { if (activeFocus && highlight === null) highlight = 0; if (!activeFocus) highlight = null; canvas.requestPaint() }

    // --- geometry ----------------------------------------------------------------------
    function k() { return Math.max(1, width / 272) }
    function barH() { return Math.max(7, Math.round(height * 0.055)) }
    function areaTop() { return barH() + 2 * k() }
    function areaH() { return height - areaTop() }

    function hitWindow(x, y, list) {
        var r = list || shownRects
        for (var i = 0; i < r.length; i++) {
            var q = r[i]
            if (x >= q[0] * width && x <= (q[0] + q[2]) * width &&
                y >= areaTop() + q[1] * areaH() && y <= areaTop() + (q[1] + q[3]) * areaH()) return i
        }
        return null
    }

    function plusBox() {
        var r = Math.max(10, 9 * k())
        return { x: width - r - 3, y: areaTop() + areaH() / 2, r: r }
    }
    function minusBox() {
        var b = plusBox()
        return { x: b.r + 3, y: b.y, r: b.r }
    }
    function minusHit(x, y) {
        if (!minusVisible || tray.length) return false
        var b = minusBox()
        return (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= (b.r + 4) * (b.r + 4)
    }
    function plusHit(x, y) {
        if (!plusVisible || tray.length) return false
        var b = plusBox()
        return (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= (b.r + 4) * (b.r + 4)
    }

    function divider() {
        // {axis, pos, value} of the line between the windows, or null.
        if (manual || !Logic.hasDivider(preset, cap)) return null
        var g = Logic.GAP
        if (preset === "columns") {
            var range = Logic.splitRange(preset)
            var v = Math.min(range[1], Math.max(range[0], split === null ? 1 / 3 : split))
            var side = ((1 - 4 * g) - (1 - 4 * g) * v) / 2
            return { axis: "x", pos: (g + side + g / 2) * width, value: v }
        }
        var s = split === null ? 0.5 : split
        var part = 1 - 3 * g
        if (preset === "stacked") return { axis: "y", pos: areaTop() + (g + part * s + g / 2) * areaH(), value: s }
        var share = preset === "master-right" ? 1 - s : s
        return { axis: "x", pos: (g + part * share + g / 2) * width, value: s }
    }
    function onDivider(x, y) {
        var d = divider()
        if (!d) return null
        var reach = Math.max(6, Logic.GAP * width * 0.7)
        var places = preset === "columns" ? [d.pos, width - d.pos] : [d.pos]
        if (y <= areaTop()) return null
        for (var i = 0; i < places.length; i++)
            if (Math.abs((d.axis === "x" ? x : y) - places[i]) <= reach) return d
        return null
    }
    function splitAt(axis, x, y) {
        var g = Logic.GAP, v
        if (preset === "columns") {
            var range = Logic.splitRange(preset)
            v = Math.min(range[1], Math.max(range[0], (2 * Math.abs(x / width - 0.5) - g) / (1 - 4 * g)))
            return Math.abs(v - 1 / 3) < 0.025 ? 0.33 : Math.round(v * 100) / 100
        }
        var share = ((axis === "x" ? x / width : (y - areaTop()) / areaH()) - 1.5 * g) / (1 - 3 * g)
        v = preset === "master-right" ? 1 - share : share
        v = Math.min(Logic.SPLIT_MAX, Math.max(Logic.SPLIT_MIN, v))
        return Math.abs(v - 0.5) < 0.025 ? 0.5 : Math.round(v * 100) / 100
    }
    function splitLabel(v) {
        if (preset === "columns") return t("pvMiddleColumn", [Math.round(v * 100)])
        var left = preset === "master-right" ? 1 - v : v
        return t("pvSplit", [Math.round(left * 100), 100 - Math.round(left * 100)])
    }
    function resultLabel(c, p) { return t("pvMax", [c, presetLabel(p)]) }
    function addLabel(c, p) { return tilesFreely ? t("pvTileWith", [c, presetLabel(p)]) : resultLabel(c, p) }

    // tray: a pill along the bottom while a window is dragged
    function trayBoxes() {
        if (!tray.length) return []
        var band = height * trayShare, label = Math.max(11, band * 0.2), pad = band * 0.1
        var th = band - 2 * pad - label, tw = th * 16 / 10, gap = tw * 0.25, n = tray.length
        var scale = Math.min(1, (width - 2 * pad) / (n * tw + (n - 1) * gap))
        tw *= scale; th *= scale; gap *= scale
        var x = (width - (n * tw + (n - 1) * gap)) / 2, y = height - band - pad
        var out = []
        for (var i = 0; i < n; i++) out.push({ x: x + i * (tw + gap), y: y, w: tw, h: th })
        return out
    }
    function trayPill() {
        var b = trayBoxes()
        if (!b.length) return null
        var band = height * trayShare, pad = band * 0.1
        return { x: b[0].x - 2 * pad, y: b[0].y - pad, w: b[b.length - 1].x + b[b.length - 1].w + 2 * pad - (b[0].x - 2 * pad), h: band + pad }
    }
    function trayHit(x, y) {
        var p = trayPill()
        if (!p || x < p.x || x > p.x + p.w || y < p.y || y > p.y + p.h) return null
        var b = trayBoxes()
        for (var i = 0; i < b.length; i++) if (x >= b[i].x - b[i].w * 0.13 && x <= b[i].x + b[i].w * 1.13) return i
        return null
    }

    function showRects(list, label, isDashed) {
        shownRects = list
        badge = label || ""
        shownDashed = Boolean(isDashed)
        canvas.requestPaint()
    }

    // --- gestures ----------------------------------------------------------------------
    function cancelDrag() {
        // Esc, another workspace, the panel closing: back as at the start. True if one ran.
        var had = drag !== null
        drag = null
        tray = []; trayHot = null; source = null; drop = false; edgeLit = false; plusAt = null
        splitLine = ""; badge = ""
        shownRects = rects; shownDashed = dashed
        highlight = activeFocus ? 0 : null
        canvas.requestPaint()
        return had
    }

    function dragStart(x, y) {
        var base = { ws: ws, cap: cap, rects: shownRects.slice(), dashed: shownDashed, moved: false }
        if (minusHit(x, y)) { drag = Object.assign(base, { mode: "minus" }); return }
        if (plusHit(x, y)) { drag = Object.assign(base, { mode: "add", x: x, y: y, preset: "", inside: false }); return }
        var d = onDivider(x, y)
        if (d) { drag = Object.assign(base, { mode: "split", axis: d.axis, start: d.value, value: d.value, x: x, y: y }); return }
        var index = hitWindow(x, y)
        if (index === null && !manual && x > width * edgeShare) { drag = Object.assign(base, { mode: "edge", x: x, next: cap }); return }
        if (index !== null)
            drag = Object.assign(base, { mode: "window", from: index, x: x, y: y, to: null, preset: "", out: false,
                                         tray: manual ? [] : trayTargets })
    }

    function dragTo(px, py) {
        var d = drag
        if (!d) return
        if (d.mode === "minus") return          // a click only
        if (d.mode === "add") {
            plusAt = { x: px, y: py }
            var inside = px >= 0 && px <= width && py >= areaTop() && py <= height
            d.inside = inside
            if (!inside) { d.preset = ""; drop = false; showRects(d.rects, t("pvDropInPreview"), d.dashed); return }
            var p = Logic.addZonePreset(addCap, px / width, (py - areaTop()) / areaH()) || presetForCap(addCap)
            d.preset = p
            drop = true
            showRects(Logic.presetRects(p, addCap, split), addLabel(addCap, p), false)
            return
        }
        if (d.mode === "split") {
            d.value = splitAt(d.axis, px, py)
            splitLine = d.axis
            showRects(Logic.presetRects(preset, cap, d.value), splitLabel(d.value), false)
            return
        }
        if (d.mode === "edge") {
            var step = Math.max(1, width / 4)
            d.next = Math.max(1, Math.min(4, d.cap + Math.round((px - d.x) / step)))
            edgeLit = true
            var ep = presetForCap(d.next)
            showRects(Logic.presetRects(ep, d.next, null), resultLabel(d.next, ep), ep === "none")
            return
        }
        // a window
        d.to = null; d.preset = ""; d.out = false
        tray = d.tray; trayHot = null; source = null
        var outside = px < 0 || py < 0 || px > width || py > height
        var hot = outside ? null : trayHit(px, py)
        if ((outside || (hot !== null && tray[hot].fewer)) && !manual && cap > 1) {
            d.out = true
            highlight = null; drop = false; trayHot = hot
            var fp = presetForCap(cap - 1)
            showRects(Logic.presetRects(fp, cap - 1, null), resultLabel(cap - 1, fp), false)
            return
        }
        if (hot !== null) {
            var target = tray[hot]
            d.preset = target.current ? "" : target.preset
            highlight = null; drop = !target.current; trayHot = hot
            showRects(Logic.presetRects(target.preset, cap, split),
                 target.current ? t("pvAlready", [presetLabel(target.preset)]) : resultLabel(cap, target.preset), false)
            return
        }
        if (!manual && cap >= 3 && d.from !== null) {
            var flip = null
            if (preset === "master-left" && d.from === 0 && px > width / 2) flip = "master-right"
            if (preset === "master-right" && d.from === cap - 1 && px < width / 2) flip = "master-left"
            if (flip) {
                d.preset = flip
                highlight = null; drop = true
                showRects(Logic.presetRects(flip, cap, split), resultLabel(cap, flip), false)
                return
            }
        }
        var to = manual ? hitWindow(px, py, d.rects) : null     // automatic layouts: no live windows to swap here
        d.to = to !== d.from ? to : null
        drop = false; source = d.from
        showRects(d.rects, d.to !== null ? t("pvSwapSaved") : "", d.dashed)
        highlight = d.to
    }

    function dragEnd() {
        var d = drag
        drag = null
        tray = []; trayHot = null; source = null; drop = false; edgeLit = false; plusAt = null; splitLine = ""
        highlight = activeFocus ? (highlight === null ? 0 : Math.min(highlight, shownRects.length - 1)) : null
        if (!d) return
        var back = function() { showRects(d.rects, "", d.dashed) }
        if (d.mode === "minus") { if (!d.moved) removeRequested(d.ws); return }
        if (d.mode === "add") {
            back()
            if (d.moved && !d.inside) return
            addRequested(d.ws, d.moved ? d.preset : "")
            return
        }
        if (d.mode === "split") { back(); if (d.value !== d.start) splitRequested(d.ws, d.value); return }
        if (d.mode === "edge" || d.out) {
            back()
            var next = d.mode === "edge" ? d.next : d.cap - 1
            if (next !== d.cap) capRequested(d.ws, next)
            return
        }
        back()
        if (d.preset) { presetRequested(d.ws, d.preset); return }
        if (d.to !== null) savedSwapRequested(d.ws, d.from, d.to)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true          // the panel scrolls: vertical drags stay here
        property real pressX: 0
        property real pressY: 0
        onPressed: function(m) {
            preview.forceActiveFocus()
            pressX = m.x; pressY = m.y
            preview.dragStart(m.x, m.y)
        }
        onPositionChanged: function(m) {
            var d = preview.drag
            if (pressed && d) {
                if (!d.moved && Math.abs(m.x - pressX) + Math.abs(m.y - pressY) <= 6) return
                d.moved = true
                preview.dragTo(m.x, m.y)
                canvas.requestPaint()
                return
            }
            // hover: the cursor tells what a press would do (same order as begin)
            var minus = preview.minusHit(m.x, m.y)
            if (minus !== preview.minusHot) { preview.minusHot = minus; canvas.requestPaint() }
            if (minus) { cursorShape = Qt.PointingHandCursor; return }
            var hot = preview.plusHit(m.x, m.y)
            if (hot !== preview.plusHot) { preview.plusHot = hot; canvas.requestPaint() }
            var div = hot ? null : preview.onDivider(m.x, m.y)
            var sh = div ? div.axis : ""
            if (sh !== preview.splitHover) { preview.splitHover = sh; canvas.requestPaint() }
            var onWindow = preview.hitWindow(m.x, m.y) !== null
            var gap = !hot && !div && !onWindow && !preview.manual && m.x > width * preview.edgeShare
            if (gap !== preview.edgeHover) { preview.edgeHover = gap; canvas.requestPaint() }
            cursorShape = hot ? Qt.PointingHandCursor : div ? (div.axis === "x" ? Qt.SplitHCursor : Qt.SplitVCursor)
                : onWindow ? Qt.OpenHandCursor : gap ? Qt.SizeHorCursor : Qt.ArrowCursor
        }
        onReleased: preview.dragEnd()
        onCanceled: preview.cancelDrag()
        onExited: { preview.minusHot = false; preview.plusHot = false; preview.splitHover = ""; preview.edgeHover = false; canvas.requestPaint() }
        onDoubleClicked: function(m) {
            // The second press started a divider drag: drop it, or its release
            // would draw the old split again.
            if (preview.onDivider(m.x, m.y)) { preview.cancelDrag(); preview.splitRequested(preview.ws, null) }
        }
    }

    // Keys: ←/→ choose a window, Shift+←/→ swap saved ones, ↑/↓ layout, [ ] size, + and −.
    Keys.onPressed: function(event) {
        var n = shownRects.length
        if (event.key === Qt.Key_Escape) { event.accepted = cancelDrag(); return }
        if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && n) {
            var cur = highlight === null ? 0 : highlight
            var next = (cur + (event.key === Qt.Key_Left ? -1 : 1) + n) % n
            if ((event.modifiers & Qt.ShiftModifier) && manual && n > 1) savedSwapRequested(ws, cur, next)
            highlight = next
            canvas.requestPaint()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight) {
            var d = divider()
            if (d) {
                var range = Logic.splitRange(preset)
                var v = Math.round(Math.min(range[1], Math.max(range[0], d.value + (event.key === Qt.Key_BracketRight ? 0.05 : -0.05))) * 100) / 100
                if (v !== d.value) splitRequested(ws, v)
            }
            event.accepted = true
            return
        }
        if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && !manual) {
            var layouts = trayTargets.filter(function(x) { return !x.fewer }).map(function(x) { return x.preset })
            if (layouts.length) {
                var i = layouts.indexOf(preset)
                var step = event.key === Qt.Key_Down ? 1 : -1
                presetRequested(ws, i < 0 ? layouts[0] : layouts[(i + step + layouts.length) % layouts.length])
            }
            event.accepted = true
            return
        }
        if ((event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) && !manual) {
            if (addCap > 0) addRequested(ws, "")
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Minus && !manual) {
            if (minusVisible) removeRequested(ws)
            event.accepted = true
        }
    }

    // --- drawing -------------------------------------------------------------------------
    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
        function rounded(ctx, x, y, w, h, r) {
            r = Math.min(r, w / 2, h / 2)
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
        }
        function dash(ctx, on) { if (ctx.setLineDash) ctx.setLineDash(on ? [4 * preview.k(), 3 * preview.k()] : []) }

        onPaint: {
            var ctx = getContext("2d")
            var W = width, H = height, K = preview.k()
            ctx.reset()
            rounded(ctx, 0, 0, W, H, preview.radius)
            ctx.clip()
            ctx.fillStyle = rgba(preview.bg, 1); ctx.fillRect(0, 0, W, H)
            if (preview.allLabel) {
                // Not a desktop: a striped template.
                ctx.strokeStyle = rgba(preview.accent, 0.07)
                var stripe = Math.max(10, W / 30)
                ctx.lineWidth = stripe * 0.35
                ctx.beginPath()
                for (var sx = -H; sx < W; sx += stripe) { ctx.moveTo(sx, H); ctx.lineTo(sx + H, 0) }
                ctx.stroke()
            } else {
                ctx.fillStyle = rgba(preview.accent, 0.12); ctx.fillRect(0, 0, W, H)
            }
            var bar = preview.barH()
            ctx.fillStyle = rgba(preview.bg, 0.92); ctx.fillRect(0, 0, W, bar)
            for (var i = 0; i < 3; i++) {
                ctx.fillStyle = rgba(i === 0 ? preview.accent : preview.fg, i === 0 ? 0.9 : 0.5)
                ctx.beginPath(); ctx.arc((6 + i * 7) * K, bar / 2, 2 * K, 0, 2 * Math.PI); ctx.fill()
            }
            ctx.fillStyle = rgba(preview.fg, 0.6); ctx.fillRect(W / 2 - 8 * K, bar / 2 - 1.2 * K, 16 * K, 2.4 * K)
            var top = preview.areaTop(), area = preview.areaH()
            var list = preview.shownRects
            for (var j = 0; j < list.length; j++) {
                var r = list[j]
                var rx = r[0] * W, ry = top + r[1] * area, rw = r[2] * W, rh = r[3] * area
                rounded(ctx, rx, ry, rw, rh, preview.small * K)
                if (preview.shownDashed || j === preview.source) {
                    ctx.fillStyle = rgba(preview.bg, 0.55); ctx.fill()
                    dash(ctx, true); ctx.strokeStyle = rgba(preview.fg, 0.6); ctx.lineWidth = 1.2 * K; ctx.stroke(); dash(ctx, false)
                    continue
                }
                ctx.fillStyle = rgba(preview.bg, 0.8); ctx.fill()
                ctx.strokeStyle = rgba(j === 0 ? preview.accent : preview.fg, j === 0 ? 0.95 : 0.35)
                ctx.lineWidth = (j === 0 ? 2 : 1.2) * K; ctx.stroke()
                if (j === preview.highlight) {
                    rounded(ctx, rx + 3 * K, ry + 3 * K, rw - 6 * K, rh - 6 * K, Math.min(preview.small, 3) * K)
                    ctx.fillStyle = rgba(preview.accent, 0.25); ctx.fill()
                    dash(ctx, true); ctx.strokeStyle = rgba(preview.accent, 1); ctx.lineWidth = 2 * K; ctx.stroke(); dash(ctx, false)
                }
                var pad = Math.max(3, rw * 0.08), line = 2.5 * K
                ctx.fillStyle = rgba(j === 0 ? preview.accent : preview.fg, 0.55)
                ctx.fillRect(rx + pad, ry + pad, Math.max(4, rw * 0.35), line)
                ctx.fillStyle = rgba(preview.fg, 0.25)
                var ly = ry + pad + line * 3
                var parts = [0.75, 0.6, 0.68, 0.4, 0.7, 0.55, 0.62, 0.3]
                for (var p = 0; p < parts.length && ly + line <= ry + rh - pad; p++) {
                    ctx.fillRect(rx + pad, ly, Math.max(4, (rw - 2 * pad) * parts[p]), line * 0.8)
                    ly += line * 2.6
                }
            }
            if (preview.drop) {
                rounded(ctx, 2, 2, W - 4, H - 4, Math.max(0, preview.radius - 2))
                if (ctx.setLineDash) ctx.setLineDash([8, 5])
                ctx.strokeStyle = rgba(preview.accent, 1); ctx.lineWidth = 3; ctx.stroke(); dash(ctx, false)
            }
            var axis = preview.splitLine || preview.splitHover
            if (axis && list.length >= 2 && !preview.tray.length) {
                ctx.fillStyle = rgba(preview.accent, preview.splitLine ? 0.95 : 0.7)
                if (axis === "x") {
                    var seen = {}
                    for (var a = 0; a < list.length; a++) for (var b = 0; b < list.length; b++) {
                        var ra = list[a], rb = list[b]
                        if (rb[0] > ra[0] + ra[2] - 0.001 && rb[0] - (ra[0] + ra[2]) < 0.1) {
                            var lx = Math.round(((ra[0] + ra[2]) + rb[0]) / 2 * 10000) / 10000
                            if (seen[lx]) continue
                            seen[lx] = true
                            ctx.fillRect(lx * W - 1.5 * K, top + area * 0.06, 3 * K, area * 0.88)
                        }
                    }
                } else {
                    var first = list[0]
                    var below = null
                    for (var c = 0; c < list.length; c++) if (list[c][1] > first[1] + first[3] - 0.001) { below = list[c]; break }
                    if (below) ctx.fillRect(W * 0.06, top + ((first[1] + first[3]) + below[1]) / 2 * area - 1.5 * K, W * 0.88, 3 * K)
                }
            }
            if (preview.tray.length) drawTray(ctx, W, H, K)
            if (preview.plusVisible && !preview.tray.length && !preview.edgeLit) {
                var pb = preview.plusBox()
                if (preview.plusAt) { drawPlus(ctx, pb.x, pb.y, pb.r, 0.35, false); pb = { x: preview.plusAt.x, y: preview.plusAt.y, r: pb.r } }
                drawPlus(ctx, pb.x, pb.y, pb.r, 1, preview.plusHot || preview.plusAt !== null)
            }
            if (preview.minusVisible && !preview.tray.length && !preview.edgeLit && !preview.plusAt) {
                var mb = preview.minusBox()
                drawPlus(ctx, mb.x, mb.y, mb.r, 1, preview.minusHot, true)
            }
            if (preview.edgeHover && !preview.edgeLit && !preview.tray.length && !preview.plusHot) {
                ctx.fillStyle = rgba(preview.fg, 0.55)
                rounded(ctx, W - 6, top + area * 0.3, 3, area * 0.4, Math.min(preview.small, 1.5)); ctx.fill()
            }
            if (preview.edgeLit) { ctx.fillStyle = rgba(preview.accent, 0.9); ctx.fillRect(W - 6, top, 4, H - top - 4) }
            if (preview.badge) {
                ctx.font = "bold " + Math.max(11, Math.round(12 * K)) + "px sans-serif"
                var tw = ctx.measureText(preview.badge).width, padB = 8 * K, bh = Math.max(11, 12 * K) + 2 * padB * 0.8
                var bw = tw + 2 * padB, bx = (W - bw) / 2, by = top + 8 * K
                rounded(ctx, bx, by, bw, bh, Math.min(preview.pill, bh / 2))
                ctx.fillStyle = rgba(preview.bg, 0.92); ctx.fill()
                ctx.strokeStyle = rgba(preview.accent, 1); ctx.lineWidth = 1.5; ctx.stroke()
                ctx.fillStyle = rgba(preview.fg, 1); ctx.textBaseline = "middle"
                ctx.fillText(preview.badge, bx + padB, by + bh / 2)
            }
            if (preview.allLabel && !preview.tray.length) {
                // A dashed accent frame and a tag: the defaults for every workspace.
                rounded(ctx, 2, 2, W - 4, H - 4, Math.max(0, preview.radius - 2))
                if (ctx.setLineDash) ctx.setLineDash([7 * K, 4 * K])
                ctx.strokeStyle = rgba(preview.accent, 0.9); ctx.lineWidth = 2 * K; ctx.stroke(); dash(ctx, false)
                ctx.font = "bold " + Math.max(10, Math.round(10 * K)) + "px sans-serif"
                var tagPad = 6 * K, tagW = ctx.measureText(preview.allLabel).width + 2 * tagPad, tagH = Math.max(10, 10 * K) + 1.4 * tagPad
                var tagX = W - tagW - 8 * K, tagY = bar + 4 * K
                rounded(ctx, tagX, tagY, tagW, tagH, Math.min(preview.pill, tagH / 2))
                ctx.fillStyle = rgba(preview.accent, 1); ctx.fill()
                ctx.fillStyle = rgba(preview.bg, 1); ctx.textBaseline = "middle"
                ctx.fillText(preview.allLabel, tagX + tagPad, tagY + tagH / 2)
            }
            if (preview.activeFocus && !preview.tray.length) {
                rounded(ctx, 1.5, 1.5, W - 3, H - 3, Math.max(0, preview.radius - 1.5))
                ctx.strokeStyle = rgba(preview.accent, 0.8); ctx.lineWidth = 2; ctx.stroke()
            }
        }

        function drawPlus(ctx, cx, cy, r, alpha, hot, minus) {
            // Round handles, square ones when the Corners setting is Square (pill 0).
            if (preview.pill > 0) { ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI) }
            else rounded(ctx, cx - r, cy - r, 2 * r, 2 * r, 0)
            ctx.fillStyle = rgba(hot ? preview.accent : preview.bg, (hot ? 0.95 : 0.9) * alpha); ctx.fill()
            ctx.strokeStyle = rgba(preview.accent, alpha); ctx.lineWidth = 1.5; ctx.stroke()
            var arm = r * 0.5
            ctx.strokeStyle = rgba(hot ? preview.bg : preview.accent, alpha); ctx.lineWidth = Math.max(2, r * 0.18)
            ctx.beginPath(); ctx.moveTo(cx - arm, cy); ctx.lineTo(cx + arm, cy)
            if (!minus) { ctx.moveTo(cx, cy - arm); ctx.lineTo(cx, cy + arm) }
            ctx.stroke()
        }

        function drawTray(ctx, W, H, K) {
            rounded(ctx, 1.5, 1.5, W - 3, H - 3, Math.max(0, preview.radius - 1.5))
            if (ctx.setLineDash) ctx.setLineDash([6, 4])
            ctx.strokeStyle = rgba(preview.fg, 0.45); ctx.lineWidth = 1.5; ctx.stroke(); dash(ctx, false)
            var band = H * preview.trayShare, pill = preview.trayPill()
            rounded(ctx, pill.x, pill.y, pill.w, pill.h, Math.min(preview.radius, 6) * K)
            ctx.fillStyle = rgba(preview.bg, 0.93); ctx.fill()
            ctx.strokeStyle = rgba(preview.fg, 0.25); ctx.lineWidth = 1; ctx.stroke()
            ctx.font = Math.max(10, Math.round(band * 0.13)) + "px sans-serif"
            ctx.textBaseline = "top"
            var boxes = preview.trayBoxes()
            for (var i = 0; i < preview.tray.length; i++) {
                var target = preview.tray[i], b = boxes[i], hot = i === preview.trayHot
                rounded(ctx, b.x, b.y, b.w, b.h, Math.min(preview.small, 3) * K)
                ctx.fillStyle = rgba(hot ? preview.accent : preview.fg, hot ? 0.22 : 0.08); ctx.fill()
                if (!hot && !target.current) dash(ctx, true)
                ctx.strokeStyle = rgba(hot || target.current ? preview.accent : preview.fg, hot ? 1 : target.current ? 0.8 : 0.35)
                ctx.lineWidth = (hot ? 2.5 : target.current ? 1.5 : 1) * K * 0.7; ctx.stroke(); dash(ctx, false)
                var inset = b.w * 0.06, shapes = Logic.presetRects(target.preset, target.cap, null)
                ctx.fillStyle = rgba(hot ? preview.accent : preview.fg, hot ? 0.7 : 0.45)
                for (var s = 0; s < shapes.length; s++) {
                    var q = shapes[s]
                    rounded(ctx, b.x + inset + q[0] * (b.w - 2 * inset), b.y + inset + q[1] * (b.h - 2 * inset),
                            q[2] * (b.w - 2 * inset), q[3] * (b.h - 2 * inset), Math.min(preview.small, 1.5) * K)
                    ctx.fill()
                }
                var label = (target.current ? "✓ " : "") + (target.fewer ? preview.t("pvOneFewer") : preview.presetLabel(target.preset))
                // The panel is narrow: a label never runs into its neighbour.
                var room = b.w * 1.2
                if (ctx.measureText(label).width > room) {
                    while (label.length > 1 && ctx.measureText(label + "…").width > room) label = label.slice(0, -1)
                    label += "…"
                }
                var lw = ctx.measureText(label).width
                ctx.fillStyle = rgba(hot || target.current ? preview.accent : preview.fg, hot || target.current ? 1 : 0.75)
                ctx.fillText(label, b.x + (b.w - lw) / 2, b.y + b.h + band * 0.04)
            }
        }
    }
}
