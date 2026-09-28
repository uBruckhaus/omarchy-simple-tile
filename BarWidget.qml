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
    readonly property bool follow: setting("follow", true) === true
    property bool opened: false
    property string lastMessage: "New windows will move when a workspace is full."
    property bool failed: false
    property var pending: []
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function open() { opened = true }
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
        text: root.failed ? "▦ !" : "▦ " + (root.tilingActive ? root.cap : "Ⅱ")
        dimmed: !root.tilingActive
        tooltipText: "Simple Tile · " + (root.tilingActive ? root.cap + " windows per workspace" : "Paused") + "\nClick for settings · Right-click to pause"
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
                description: "Move new windows when the workspace is full"
                checked: root.tilingActive
                onClicked: root.updateSetting("active", !root.tilingActive)
            }
            Text {
                text: "WINDOWS PER WORKSPACE"
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
                    model: 8
                    Ui.Button {
                        required property int index
                        width: (content.width - Style.space(18)) / 4
                        text: String(index + 1)
                        selected: root.cap === index + 1
                        bordered: true
                        focusable: true
                        onClicked: root.updateSetting("maxWindows", index + 1)
                        Accessible.name: (index + 1) + " windows per workspace"
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
