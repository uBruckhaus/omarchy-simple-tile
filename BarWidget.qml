import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui as Ui

Ui.BarWidget {
    id: root
    moduleName: "ubruckhaus.simple-tile"
    readonly property bool tilingActive: setting("active", true) === true
    readonly property int cap: Math.max(1, Math.min(8, Number(setting("maxWindows", 2)) || 2))
    readonly property var workspaceCaps: setting("workspaceCaps", {}) || ({})
    readonly property bool follow: setting("follow", true) === true
    readonly property int currentWsId: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0) ? Hyprland.focusedWorkspace.id : 1
    property int selectedWorkspace: 0
    property bool opened: false
    property string lastMessage: "New windows move on overflow. Manual moves (e.g. Super+Shift+N) override the limit as intended."
    property bool failed: false
    property var pending: []
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onOpenedChanged: {
        if (opened) {
            selectedWorkspace = root.currentWsId > 0 ? root.currentWsId : 0
        }
    }

    function hasCustomCap(wsId) {
        if (!wsId || wsId <= 0 || !workspaceCaps) return false
        var val = workspaceCaps[String(wsId)]
        return typeof val === "number" && val >= 1 && val <= 8
    }

    function capForWorkspace(wsId) {
        if (hasCustomCap(wsId)) {
            return Number(workspaceCaps[String(wsId)])
        }
        return root.cap
    }

    function effectiveCapFor(wsId) {
        if (wsId === 0) return root.cap
        return capForWorkspace(wsId)
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
        list.sort(function(a, b) { return a - b })
        return list
    }

    function setWorkspaceCap(wsId, newCap) {
        var current = Object.assign({}, workspaceCaps)
        current[String(wsId)] = newCap
        updateSetting("workspaceCaps", current)
    }

    function resetWorkspaceCap(wsId) {
        var current = Object.assign({}, workspaceCaps)
        delete current[String(wsId)]
        updateSetting("workspaceCaps", current)
    }

    function open() {
        selectedWorkspace = root.currentWsId > 0 ? root.currentWsId : 0
        opened = true
    }
    function close() { opened = false }
    function closeForPopoutSwitch() { close() }
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
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("simple_tile.py").toString().replace(/^file:\/\//, "")), "--window", address]
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

    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.failed ? "▦ !" : "▦"
        fontSize: Style.font.icon
        active: root.failed
        dimmed: !root.tilingActive
        tooltipText: {
            if (!root.tilingActive) return "Simple Tile · Paused\nClick for settings · Right-click to resume"
            if (root.activeWsCustom) {
                return "Simple Tile · Workspace " + root.currentWsId + ": " + root.activeWsCap + " windows (custom, default: " + root.cap + ")\nClick for settings · Right-click to pause"
            }
            return "Simple Tile · Workspace " + root.currentWsId + ": " + root.cap + " windows per workspace\nClick for settings · Right-click to pause"
        }
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.RightButton) root.updateSetting("active", !root.tilingActive)
            else root.opened = !root.opened
        }
    }

    Ui.KeyboardPanel {
        id: popup
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        focusTarget: content
        contentWidth: fittedContentWidth(Style.space(340))
        contentHeight: fittedContentHeight(content.implicitHeight)

        Column {
            id: content
            width: parent.width
            spacing: Style.space(14)
            Keys.onEscapePressed: root.close()

            Text {
                text: "Simple Tile"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
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
                label: root.tilingActive ? "Automatic tiling" : "Tiling paused"
                description: "Move new windows when full · Manual moves override"
                checked: root.tilingActive
                onClicked: root.updateSetting("active", !root.tilingActive)
            }
            Text {
                text: "WORKSPACES"
                color: Color.foreground
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
            }
            Ui.Button {
                id: allCard
                width: parent.width
                implicitHeight: Style.space(34)
                selected: root.selectedWorkspace === 0
                bordered: true
                focusable: true
                onClicked: root.selectedWorkspace = 0
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
                columns: 5
                spacing: Style.space(6)
                Repeater {
                    model: root.workspaceList
                    Ui.Button {
                        id: wsCard
                        required property int modelData
                        width: (content.width - Style.space(24)) / 5
                        implicitHeight: Style.space(46)
                        selected: root.selectedWorkspace === modelData
                        bordered: true
                        focusable: true
                        tooltipText: "Workspace " + modelData + (modelData === root.currentWsId ? " (Active)" : "") + "\nLimit: " + root.capForWorkspace(modelData) + " windows" + (root.hasCustomCap(modelData) ? " (custom)" : " (default)")
                        onClicked: root.selectedWorkspace = modelData
                        Accessible.name: "Workspace " + modelData

                        Item {
                            anchors.fill: parent
                            anchors.topMargin: Style.space(4)
                            anchors.bottomMargin: Style.space(4)
                            anchors.leftMargin: Style.space(6)
                            anchors.rightMargin: Style.space(6)
                            enabled: false

                            Row {
                                id: cardHeader
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: Style.space(13)

                                Text {
                                    text: "WS " + wsCard.modelData
                                    color: Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    opacity: wsCard.selected ? 1.0 : 0.8
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Item {
                                    width: 1
                                    height: 1
                                    anchors.right: activeDot.left
                                }

                                Rectangle {
                                    id: activeDot
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Style.space(5)
                                    height: Style.space(5)
                                    radius: width / 2
                                    color: Color.accent
                                    visible: wsCard.modelData === root.currentWsId
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

                            Text {
                                anchors.top: cardDivider.bottom
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "▦ " + root.capForWorkspace(wsCard.modelData)
                                color: root.hasCustomCap(wsCard.modelData) ? Color.accent : Color.foreground
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                                font.bold: root.hasCustomCap(wsCard.modelData) || wsCard.selected
                                opacity: (root.hasCustomCap(wsCard.modelData) || wsCard.selected) ? 1.0 : 0.65
                            }
                        }
                    }
                }
            }
            Text {
                text: root.selectedWorkspace === 0
                    ? "WINDOW LIMIT (DEFAULT)"
                    : ("WINDOW LIMIT FOR WORKSPACE " + root.selectedWorkspace + (root.hasCustomCap(root.selectedWorkspace) ? " (CUSTOM)" : " (DEFAULT: " + root.cap + ")"))
                color: Color.foreground
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
            }
            Ui.Button {
                visible: root.selectedWorkspace > 0 && root.hasCustomCap(root.selectedWorkspace)
                width: parent.width
                text: "Reset workspace " + root.selectedWorkspace + " to default (" + root.cap + ")"
                bordered: true
                focusable: true
                fontSize: Style.font.caption
                onClicked: root.resetWorkspaceCap(root.selectedWorkspace)
            }
            Grid {
                width: parent.width
                columns: 4
                spacing: Style.space(6)
                Repeater {
                    model: 8
                    Ui.Button {
                        required property int index
                        width: (content.width - Style.space(18)) / 4
                        text: String(index + 1)
                        selected: root.effectiveCapFor(root.selectedWorkspace) === index + 1
                        bordered: true
                        focusable: true
                        onClicked: {
                            if (root.selectedWorkspace === 0) {
                                root.updateSetting("maxWindows", index + 1)
                            } else {
                                root.setWorkspaceCap(root.selectedWorkspace, index + 1)
                            }
                        }
                        Accessible.name: (index + 1) + " windows"
                    }
                }
            }
            Ui.Toggle {
                width: parent.width
                label: "Follow the window"
                description: "Switch to the overflow workspace"
                checked: root.follow
                onClicked: root.updateSetting("follow", !root.follow)
            }
            Text {
                width: parent.width
                text: root.failed ? root.lastMessage : (root.tilingActive ? root.lastMessage : "Your windows stay where you put them.")
                wrapMode: Text.WordWrap
                color: root.failed ? Color.urgent : Color.foreground
                opacity: root.failed ? 1 : 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
    }
}
