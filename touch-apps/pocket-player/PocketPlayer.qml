import QtQuick 2.4
import QtQuick.Layouts 1.1
import QtMultimedia 5.0
import Ubuntu.Components 1.3
import Ubuntu.Content 1.3

MainView {
    id: app
    applicationName: "pocket-player.touchapps"
    width: units.gu(45)
    height: units.gu(72)
    automaticOrientation: true
    backgroundColor: "#11161d"

    property var pendingTransfer: null
    property var currentTransfer: null
    property bool picking: false
    property bool expanded: false
    property string fileName: ""
    property string message: ""
    property url originalFile: ""
    property int selectedFile: 0
    property int servicePort: 0
    property string serviceToken: ""
    property bool attempted: false
    property bool converting: false
    property bool compatibilityCopy: false
    property bool streamingCopy: false
    property bool streamFailed: false
    readonly property color accent: "#ff996b"
    readonly property color foreground: "#f3efe9"
    readonly property color secondary: "#a6b2c0"

    function requestConversion(action, source, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:" + servicePort + "/conversion")
        xhr.setRequestHeader("Authorization", "Bearer " + serviceToken)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 200)
                callback(JSON.parse(xhr.responseText))
            else
                callback({ state: "failed", error: "The compatibility service could not respond." })
        }
        xhr.send(JSON.stringify({ action: action, source: source || "" }))
    }

    function conversionResult(result, selection) {
        if (selection !== selectedFile || !converting)
            return
        if (result.state === "working")
            return
        converting = false
        if (result.state === "ready") {
            compatibilityCopy = true
            streamingCopy = !!result.streaming
            message = streamingCopy ? "Starting playback…" : ""
            playback.source = result.url
            playback.play()
        } else if (result.state === "failed") {
            message = result.error
        }
    }

    function startCompatibility(prepareCopy) {
        if (converting || originalFile.toString() === "" || !servicePort)
            return
        attempted = true
        converting = true
        compatibilityCopy = false
        streamingCopy = false
        streamFailed = false
        expanded = false
        message = prepareCopy ? "Preparing a full copy. This may take a while." : "Preparing playback…"
        playback.stop()
        playback.source = ""
        var selection = ++selectedFile
        requestConversion(prepareCopy ? "prepare-copy" : "start", originalFile.toString(), function(result) {
            conversionResult(result, selection)
        })
    }

    function cancelCompatibility() {
        if (!converting)
            return
        selectedFile++
        converting = false
        message = "Conversion canceled."
        requestConversion("cancel", "", function() {})
    }

    Component.onCompleted: {
        var prefix = "--pocket-config="
        var args = Qt.application.arguments
        var path = ""
        for (var index = 0; index < args.length; index++) {
            if (args[index].indexOf(prefix) === 0)
                path = args[index].slice(prefix.length)
        }
        if (path === "")
            return
        var config = new XMLHttpRequest()
        config.open("GET", "file://" + encodeURI(path))
        config.onreadystatechange = function() {
            if (config.readyState !== XMLHttpRequest.DONE)
                return
            if (config.status === 200) {
                var descriptor = JSON.parse(config.responseText)
                servicePort = descriptor.port
                serviceToken = descriptor.token
            } else {
                message = "Compatibility mode is unavailable."
            }
        }
        config.send()
    }

    Timer {
        interval: 1200
        repeat: true
        running: converting && Qt.application.state === Qt.ApplicationActive
        onTriggered: {
            var selection = selectedFile
            requestConversion("status", "", function(result) {
                conversionResult(result, selection)
            })
        }
    }

    function elapsed(milliseconds) {
        var seconds = Math.max(0, Math.floor(milliseconds / 1000))
        var minutes = Math.floor(seconds / 60)
        var hours = Math.floor(minutes / 60)
        function two(number) { return number < 10 ? "0" + number : "" + number }
        return hours > 0 ? hours + ":" + two(minutes % 60) + ":" + two(seconds % 60)
                         : minutes + ":" + two(seconds % 60)
    }

    function nameFor(url) {
        var path = url.toString().split("/")
        var last = path[path.length - 1]
        try {
            return decodeURIComponent(last)
        } catch (error) {
            return last
        }
    }

    function openMedia(url, transfer) {
        if (url.toString().indexOf("file:///") !== 0) {
            message = "Choose an audio or video file stored on the device."
            return
        }

        playback.stop()
        playback.source = ""
        if (currentTransfer && currentTransfer !== transfer &&
                currentTransfer.state === ContentTransfer.Collected)
            currentTransfer.finalize()

        cancelCompatibility()
        selectedFile++
        currentTransfer = transfer
        originalFile = url
        attempted = false
        compatibilityCopy = false
        streamingCopy = false
        streamFailed = false
        fileName = nameFor(url)
        message = ""
        playback.source = url
        playback.play()
    }

    function watchTransfer(transfer) {
        if (!transfer) {
            message = "File Manager could not start a file transfer."
            picking = false
            return
        }
        pendingTransfer = transfer
        picking = false
        readTransfer()
    }

    function readTransfer() {
        if (!pendingTransfer)
            return
        var transfer = pendingTransfer
        if (transfer.state === ContentTransfer.Charged ||
                transfer.state === ContentTransfer.Collected) {
            var items = transfer.items
            pendingTransfer = null
            if (items && items.length > 0)
                openMedia(items[0].url, transfer)
            else
                message = "No file was received."
        } else if (transfer.state === ContentTransfer.Aborted) {
            pendingTransfer = null
        }
    }

    function togglePlayback() {
        if (playback.playbackState === MediaPlayer.PlayingState) {
            playback.pause()
        } else {
            if (playback.source.toString() === "" && fileName !== "")
                playback.source = originalFile
            if (playback.status === MediaPlayer.EndOfMedia && playback.seekable)
                playback.seek(0)
            playback.play()
        }
    }

    function seekTo(position) {
        if (playback.seekable)
            playback.seek(Math.max(0, Math.min(playback.duration, position)))
    }

    MediaPlayer {
        id: playback
        onPositionChanged: {
            if (app.streamingCopy && position > 0 && app.message === "Starting playback…")
                app.message = ""
        }
        onError: {
            if (error === MediaPlayer.NoError)
                return
            if (servicePort && !attempted && playback.source.toString() === originalFile.toString()) {
                var selection = selectedFile
                Qt.callLater(function() {
                    if (selection === selectedFile && !attempted)
                        app.startCompatibility()
                })
                return
            }
            app.expanded = false
            if (app.streamingCopy) {
                app.streamingCopy = false
                app.compatibilityCopy = false
                app.streamFailed = true
                app.message = "The media engine could not play the stream. You can prepare a full copy."
            } else {
                app.message = "This file could not be played. " + errorString
            }
        }
    }

    Connections {
        target: ContentHub
        onImportRequested: app.watchTransfer(transfer)
    }

    Connections {
        target: pendingTransfer
        onStateChanged: app.readTransfer()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: units.gu(7.5)
            visible: !app.expanded
            color: "#19212b"

            RowLayout {
                anchors.fill: parent
                anchors.margins: units.gu(1.25)
                spacing: units.gu(1.5)

                Text {
                    Layout.fillWidth: true
                    text: "Pocket Player"
                    color: app.foreground
                    font.pixelSize: units.gu(2.6)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Button {
                    text: "Open file"
                    color: app.accent
                    enabled: !pendingTransfer && !converting
                    onClicked: {
                        app.message = ""
                        app.picking = true
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: app.expanded ? 0 : units.gu(1.5)
                color: "#0a0d12"
                radius: app.expanded ? 0 : units.gu(1.4)
                clip: true

                VideoOutput {
                    anchors.fill: parent
                    source: playback
                    fillMode: VideoOutput.PreserveAspectFit
                    visible: playback.hasVideo
                }

                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - units.gu(4), units.gu(40))
                    spacing: units.gu(1.25)
                    visible: !playback.hasVideo

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: units.gu(7)
                        height: width
                        radius: units.gu(1.4)
                        color: "#243041"

                        Text {
                            anchors.centerIn: parent
                            text: app.fileName === "" ? "▶" : "♫"
                            font.pixelSize: units.gu(3)
                            color: app.accent
                        }
                    }

                    Text {
                        width: parent.width
                        text: app.fileName === "" ? "Open an audio or video file" : app.fileName
                        color: app.foreground
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        font.pixelSize: units.gu(2.1)
                    }
                }

                Button {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: units.gu(1)
                    text: app.expanded ? "Show controls" : "Expand"
                    visible: playback.hasVideo || app.expanded
                    onClicked: app.expanded = !app.expanded
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: units.gu(1.5)
            Layout.rightMargin: units.gu(1.5)
            visible: app.message !== "" && !app.expanded
            text: app.message
            color: app.accent
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.pixelSize: units.gu(1.75)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: units.gu(1.5)
            Layout.rightMargin: units.gu(1.5)
            Layout.topMargin: units.gu(1)
            Layout.bottomMargin: units.gu(1.5)
            visible: !app.expanded
            spacing: units.gu(0.6)

            Text {
                Layout.fillWidth: true
                visible: app.fileName !== "" && playback.hasVideo
                text: app.fileName
                textFormat: Text.PlainText
                color: app.foreground
                font.pixelSize: units.gu(1.9)
                elide: Text.ElideMiddle
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: units.gu(4)
                property real scrub: 0
                readonly property real progress: timeline.pressed ? scrub :
                    playback.duration > 0 ? Math.min(1, playback.position / playback.duration) : 0

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: units.gu(0.5)
                    radius: height / 2
                    color: "#354356"

                    Rectangle {
                        width: parent.width * parent.parent.progress
                        height: parent.height
                        radius: parent.radius
                        color: app.accent
                    }
                }

                MouseArea {
                    id: timeline
                    anchors.fill: parent
                    enabled: playback.seekable && playback.duration > 0
                    function at(x) { return Math.max(0, Math.min(1, x / width)) }
                    onPressed: parent.scrub = at(mouse.x)
                    onPositionChanged: {
                        if (pressed)
                            parent.scrub = at(mouse.x)
                    }
                    onReleased: app.seekTo(at(mouse.x) * playback.duration)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: app.elapsed(playback.position)
                    color: app.secondary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: playback.duration > 0 ? app.elapsed(playback.duration) : "–:––"
                    color: app.secondary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.7)

                Button {
                    text: "−10 s"
                    Layout.fillWidth: true
                    enabled: playback.seekable
                    onClicked: app.seekTo(playback.position - 10000)
                }
                Button {
                    text: playback.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                    color: app.accent
                    Layout.fillWidth: true
                    enabled: app.fileName !== "" && !converting && playback.status !== MediaPlayer.InvalidMedia
                    onClicked: app.togglePlayback()
                }
                Button {
                    text: "+10 s"
                    Layout.fillWidth: true
                    enabled: playback.seekable
                    onClicked: app.seekTo(playback.position + 10000)
                }
                Button {
                    text: playback.muted ? "Unmute" : "Mute"
                    Layout.fillWidth: true
                    enabled: app.fileName !== ""
                    onClicked: playback.muted = !playback.muted
                }
            }

            Button {
                Layout.fillWidth: true
                visible: app.servicePort > 0 && app.fileName !== ""
                enabled: app.converting || !app.compatibilityCopy
                text: app.converting ? "Cancel conversion" : app.streamFailed ? "Prepare a full copy" : "Play in compatibility mode"
                onClicked: {
                    if (app.converting)
                        app.cancelCompatibility()
                    else
                        app.startCompatibility(app.streamFailed)
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: app.picking
        z: 2

        sourceComponent: Rectangle {
            color: app.backgroundColor

            ContentPeerPicker {
                anchors.fill: parent
                contentType: ContentType.All
                handler: ContentHandler.Source
                onPeerSelected: {
                    peer.selectionType = ContentTransfer.Single
                    app.watchTransfer(peer.request())
                }
                onCancelPressed: app.picking = false
            }
        }
    }

    ContentTransferHint {
        anchors.fill: parent
        z: 3
        activeTransfer: pendingTransfer
    }
}
