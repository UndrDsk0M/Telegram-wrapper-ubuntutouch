import QtQuick 2.4
import QtQuick.Layouts 1.1
import Ubuntu.Components 1.3
import Ubuntu.Components.Popups 1.3

MainView {
    id: app
    objectName: "sparrowChat"
    applicationName: "sparrow-chat.touchwrapper"
    width: units.gu(42)
    height: units.gu(73)
    backgroundColor: "#f3f6f2"
    anchorToKeyboard: true

    property string stage: "connect"
    property string status: ""
    property bool busy: true
    property bool showWorking: true
    property var chats: []
    property var messages: []
    property string activeChat: ""
    property string activeTitle: ""
    property bool moreHistory: true
    property bool downloadsOpen: false
    property var downloadFiles: []
    property bool downloading: false
    property int scanBefore: 0
    property bool canScan: false
    property string saveUrl: ""
    property string openKind: ""
    property string previewUrl: ""
    property var pendingFile: null
    onActiveChatChanged: pendingFile = null
    property color ink: "#1b352d"
    property color muted: "#526860"
    property int servicePort: 0
    property string serviceToken: ""
    property color accent: "#245e50"

    function request(action, fields, onSuccess, quiet, onFailure) {
        if (busy)
            return
        var payload = fields || {}
        payload.action = action
        busy = true
        showWorking = !quiet
        status = ""
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:" + servicePort + "/command")
        xhr.setRequestHeader("Authorization", "Bearer " + serviceToken)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            busy = false
            if (xhr.status !== 200) {
                status = "The Telegram service could not respond."
                if (onFailure)
                    onFailure()
                return
            }
            var response = JSON.parse(xhr.responseText)
            var previous = stage
            stage = response.stage
            if (stage !== previous)
                signValue.text = ""
            if (response.error) {
                status = response.error
                if (onFailure)
                    onFailure()
                return
            }
            if (stage !== "chats") {
                downloadsOpen = false
                downloadFiles = []
                downloading = false
                saveUrl = ""
                openKind = ""
                previewUrl = ""
                pendingFile = null
            }
            if (stage === "chats" && previous !== stage)
                refreshChats()
            if (onSuccess)
                onSuccess(response)
        }
        xhr.send(JSON.stringify(payload))
    }

    function refreshChats(quiet) {
        request("list", {}, function(response) {
            if (JSON.stringify(response.chats) !== JSON.stringify(chats))
                chats = response.chats
        }, quiet)
    }

    function loadHistory(before, scrollToEnd, quiet) {
        request("history", { chat: activeChat, before: before, read: scrollToEnd || historyView.atYEnd }, function(response) {
            var page = response.messages || []
            var previousLength = messages.length
            if (before > 0) {
                moreHistory = page.length === 30 && previousLength + page.length < 300
                if (page.length === 0)
                    return
                messages = page.concat(messages)
                historyView.positionViewAtIndex(page.length, ListView.Beginning)
                return
            }
            if (previousLength > 30 && page.length > 0) {
                var firstRecent = page[0].id
                var older = messages.filter(function(item) { return item.id < firstRecent })
                page = older.concat(page)
            } else {
                moreHistory = page.length === 30
            }
            var atEnd = historyView.atYEnd
            if (JSON.stringify(page) !== JSON.stringify(messages)) {
                messages = page
                if (atEnd || scrollToEnd)
                    historyView.positionViewAtEnd()
            }
        }, quiet)
    }

    function refreshDownloads(action, id, quiet) {
        request(action || "downloads", { chat: activeChat, value: id || "" }, function(response) {
            var files = response.files || []
            if (JSON.stringify(files) !== JSON.stringify(downloadFiles))
                downloadFiles = files
            downloading = response.downloading
            if (pendingFile)
                checkFile(files)
        }, quiet, function() { pendingFile = null })
    }

    function openAttachment(id) {
        pendingFile = { id: id, started: false }
        refreshDownloads()
    }

    function checkFile(files) {
        var target = pendingFile
        var file = null
        for (var index = 0; index < files.length; index++) {
            var item = files[index]
            if (item.id === target.id) {
                file = item
                break
            }
        }
        if (!file) {
            pendingFile = null
            status = "This attachment is unavailable. Reopen the chat and try again."
            return
        }
        if (file.state === "saved") {
            pendingFile = null
            if (file.kind === "Photo" || file.kind === "Image") {
                previewUrl = file.url
            } else {
                openKind = file.kind
                saveUrl = file.url
            }
        } else if (file.state === "downloading") {
            target.started = true
        } else if (target.started) {
            pendingFile = null
            status = file.error || "The download stopped. Tap the file to retry."
        } else {
            target.started = true
            refreshDownloads("download", file.id)
        }
    }

    function openDownloads() {
        downloadsOpen = true
        downloadFiles = []
        scanBefore = messages.length > 0 ? messages[0].id : 0
        canScan = activeChat !== "" && messages.length >= 30
        refreshDownloads()
    }

    function scanOlderFiles() {
        request("history", { chat: activeChat, before: scanBefore }, function(response) {
            var page = response.messages || []
            if (page.length > 0)
                scanBefore = page[0].id
            canScan = page.length === 30
            refreshDownloads()
        })
    }

    function openChat(chat) {
        downloadsOpen = false
        activeChat = chat.key
        activeTitle = chat.title
        moreHistory = true
        messages = []
        composer.text = ""
        loadHistory(0, true)
    }

    function submitSignIn() {
        if (stage === "setup") {
            request("configure", { id: apiID.text, hash: apiHash.text }, function() {
                apiID.text = ""
                apiHash.text = ""
            })
        } else {
            request("auth", { value: signValue.text }, function() { signValue.text = "" })
        }
    }

    function sendMessage() {
        request("send", { chat: activeChat, value: composer.text }, function() {
            composer.text = ""
            loadHistory(0, true)
        })
    }

    Component.onCompleted: {
        var prefix = "--sparrow-config="
        var args = Qt.application.arguments
        var path = ""
        for (var index = 0; index < args.length; index++) {
            if (args[index].indexOf(prefix) === 0)
                path = args[index].slice(prefix.length)
        }
        if (path === "") {
            busy = false
            status = "Open Sparrow Chat from the app drawer."
            return
        }
        var file = new XMLHttpRequest()
        file.open("GET", "file://" + encodeURI(path))
        file.onreadystatechange = function() {
            if (file.readyState !== XMLHttpRequest.DONE)
                return
            busy = false
            if (file.status !== 200) {
                status = "Sparrow Chat could not start its Telegram service."
                return
            }
            var descriptor = JSON.parse(file.responseText)
            servicePort = descriptor.port
            serviceToken = descriptor.token
            request("start")
        }
        file.send()
    }

    Timer {
        interval: 1200
        running: pendingFile !== null && Qt.application.state === Qt.ApplicationActive
        repeat: true
        onTriggered: {
            if (!busy)
                refreshDownloads("downloads", "", true)
        }
    }

    Timer {
        interval: downloadsOpen ? (downloading ? 1200 : 12000) : (activeChat === "" ? 25000 : 12000)
        running: stage === "chats" && Qt.application.state === Qt.ApplicationActive
        repeat: true
        onTriggered: {
            if (busy || pendingFile || status !== "")
                return
            if (downloadsOpen) {
                if (downloading || activeChat === "") {
                    refreshDownloads("downloads", "", true)
                } else {
                    request("history", { chat: activeChat }, function() {
                        refreshDownloads("downloads", "", true)
                    }, true)
                }
            } else if (activeChat === "")
                refreshChats(true)
            else
                loadHistory(0, false, true)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: units.gu(7)
            color: app.accent

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: units.gu(2)
                anchors.rightMargin: units.gu(2)
                spacing: units.gu(1)

                Button {
                    visible: stage === "chats" && (downloadsOpen || activeChat !== "")
                    text: "Back"
                    enabled: !busy
                    onClicked: {
                        if (downloadsOpen) {
                            downloadsOpen = false
                            return
                        }
                        activeChat = ""
                        messages = []
                        composer.text = ""
                        refreshChats()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: downloadsOpen ? "Downloads" : stage === "chats" && activeChat !== "" ? activeTitle : "Sparrow Chat"
                    color: "white"
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: units.gu(2.45)
                    font.bold: true
                }

                Button {
                    visible: stage === "chats" && !downloadsOpen && activeChat === ""
                    text: "Sign out"
                    enabled: !busy
                    onClicked: PopupUtils.open(logoutDialog)
                }

                Button {
                    visible: stage === "chats" && !downloadsOpen && activeChat !== ""
                    text: "Refresh"
                    enabled: !busy
                    onClicked: loadHistory(0, false)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? notice.implicitHeight + units.gu(2) : 0
            visible: status !== "" || pendingFile !== null || (busy && showWorking)
            color: status === "" ? "#dcece6" : "#fae8dd"
            Text {
                id: notice
                anchors.centerIn: parent
                width: parent.width - units.gu(4)
                text: status !== "" ? status : pendingFile ? "Downloading attachment…" : "Working…"
                color: app.ink
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font.pixelSize: units.gu(1.65)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: units.gu(1)
            Layout.rightMargin: units.gu(1)
            Layout.topMargin: units.gu(1)
            Layout.bottomMargin: units.gu(1)
            visible: stage === "chats"

            Button {
                Layout.fillWidth: true
                text: activeChat === "" ? "Chats" : "Messages"
                color: !downloadsOpen ? app.accent : UbuntuColors.lightGrey
                enabled: !busy
                onClicked: downloadsOpen = false
            }

            Button {
                Layout.fillWidth: true
                text: "Downloads"
                color: downloadsOpen ? app.accent : UbuntuColors.lightGrey
                enabled: !busy
                onClicked: {
                    if (!downloadsOpen)
                        openDownloads()
                }
            }
        }

        DownloadsPane {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: stage === "chats" && downloadsOpen
            files: downloadFiles
            transferring: downloading
            busy: app.busy
            canScan: app.canScan
            chatTitle: activeChat === "" ? "" : activeTitle
            onDownload: refreshDownloads("download", id)
            onCancel: refreshDownloads("cancel-download", id)
            onScan: scanOlderFiles()
            onOpenFile: openAttachment(id)
            onSave: {
                openKind = ""
                saveUrl = url
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: stage !== "chats"

            Flickable {
                anchors.fill: parent
                contentHeight: signForm.height + units.gu(5)
                clip: true

                ColumnLayout {
                    id: signForm
                    x: (parent.width - width) / 2
                    y: units.gu(3)
                    width: Math.min(parent.width - units.gu(5), units.gu(52))
                    spacing: units.gu(1.5)

                    Text {
                        Layout.fillWidth: true
                        text: stage === "setup" ? "Connect your app" : "Sign in to Telegram"
                        color: app.ink
                        font.pixelSize: units.gu(3)
                        font.bold: true
                        wrapMode: Text.Wrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (stage === "setup")
                                return "Get your API ID and API hash from API development tools at my.telegram.org."
                            if (stage === "phone")
                                return "Enter your phone number with its country code."
                            if (stage === "code")
                                return "Enter the verification code sent by Telegram."
                            if (stage === "password")
                                return "Enter your Telegram two-step verification password."
                            return "Connect to Telegram to continue."
                        }
                        color: app.muted
                        font.pixelSize: units.gu(1.9)
                        wrapMode: Text.Wrap
                    }

                    TextField {
                        id: apiID
                        Layout.fillWidth: true
                        visible: stage === "setup"
                        placeholderText: "API ID"
                        enabled: !busy
                        inputMethodHints: Qt.ImhDigitsOnly
                    }

                    TextField {
                        id: apiHash
                        Layout.fillWidth: true
                        visible: stage === "setup"
                        placeholderText: "API hash"
                        enabled: !busy
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                    }

                    TextField {
                        id: signValue
                        Layout.fillWidth: true
                        visible: stage === "phone" || stage === "code" || stage === "password"
                        placeholderText: stage === "phone" ? "+123456789" : stage === "code" ? "Verification code" : "Password"
                        enabled: !busy
                        echoMode: stage === "phone" ? TextInput.Normal : TextInput.Password
                        inputMethodHints: stage === "phone" ? Qt.ImhDialableCharactersOnly : Qt.ImhSensitiveData
                        onAccepted: submitSignIn()
                    }

                    Button {
                        Layout.fillWidth: true
                        text: stage === "connect" ? "Retry" : stage === "phone" ? "Send code" : "Continue"
                        color: app.accent
                        enabled: !busy
                        onClicked: stage === "connect" ? request("start") : submitSignIn()
                    }

                    Button {
                        Layout.fillWidth: true
                        visible: stage !== "setup"
                        text: stage === "code" || stage === "password" ? "Use another number" : "Edit API credentials"
                        enabled: !busy
                        onClicked: request(stage === "code" || stage === "password" ? "restart-sign-in" : "setup")
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: stage === "chats" && !downloadsOpen && activeChat === ""
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: units.gu(1.5)
                Layout.rightMargin: units.gu(1.5)
                Layout.topMargin: units.gu(1.5)
                Layout.bottomMargin: units.gu(1.5)
                Text {
                    Layout.fillWidth: true
                    text: "Recent chats"
                    font.bold: true
                    font.pixelSize: units.gu(2.2)
                    color: app.ink
                }
                Button {
                    text: "Refresh"
                    enabled: !busy
                    onClicked: refreshChats()
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: app.chats
                delegate: Rectangle {
                    width: ListView.view.width
                    height: units.gu(8)
                    color: index % 2 === 0 ? "#ffffff" : "#f8faf8"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: units.gu(1.5)
                        spacing: units.gu(1.5)

                        Rectangle {
                            Layout.preferredWidth: units.gu(4.6)
                            Layout.preferredHeight: width
                            radius: width / 2
                            color: "#dcece6"
                            Text {
                                anchors.centerIn: parent
                                text: modelData.title.slice(0, 1).toUpperCase()
                                textFormat: Text.PlainText
                                color: app.accent
                                font.bold: true
                                font.pixelSize: units.gu(2.2)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: units.gu(0.4)

                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: app.ink
                                font.bold: true
                                font.pixelSize: units.gu(2)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.text.replace(/\s+/g, " ")
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: app.muted
                                font.pixelSize: units.gu(1.65)
                            }
                        }

                        Text {
                            text: modelData.unread > 0 ? modelData.unread : ""
                            color: app.accent
                            font.bold: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !busy
                        onClicked: openChat(modelData)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: app.chats.length === 0 && !busy
                    text: "No recent chats"
                    color: app.muted
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: stage === "chats" && !downloadsOpen && activeChat !== ""
            spacing: 0

            ListView {
                id: historyView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: units.gu(1)
                model: app.messages

                header: Button {
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    visible: app.moreHistory && app.messages.length > 0
                    text: "Load older messages"
                    enabled: !busy
                    onClicked: loadHistory(app.messages[0].id, false)
                }

                delegate: Item {
                    width: ListView.view.width
                    height: bubble.height
                    Rectangle {
                        id: bubble
                        x: modelData.mine ? parent.width - width - units.gu(1.5) : units.gu(1.5)
                        width: Math.min(parent.width - units.gu(6), units.gu(58))
                        height: contents.implicitHeight + units.gu(2)
                        radius: units.gu(1.3)
                        color: modelData.mine ? "#dcece6" : "#ffffff"

                        Column {
                            id: contents
                            anchors.centerIn: parent
                            width: parent.width - units.gu(2.2)
                            spacing: units.gu(0.4)

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: modelData.sender
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: app.accent
                                font.bold: true
                                font.pixelSize: units.gu(1.5)
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: modelData.text
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: app.ink
                                font.pixelSize: units.gu(2)
                            }
                            Button {
                                width: parent.width
                                visible: !!modelData.attachmentId
                                text: modelData.attachment || ""
                                enabled: !busy
                                onClicked: openAttachment(modelData.attachmentId)
                            }
                            Text {
                                width: parent.width
                                text: Qt.formatDateTime(new Date(modelData.time * 1000), "MMM d · hh:mm")
                                color: app.muted
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: units.gu(1.35)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: units.gu(1)
                spacing: units.gu(1)

                TextField {
                    id: composer
                    Layout.fillWidth: true
                    placeholderText: "Message"
                    maximumLength: 4096
                    onAccepted: {
                        if (!busy && text.trim().length > 0)
                            sendMessage()
                    }
                }
                Button {
                    text: "Send"
                    color: app.accent
                    enabled: !busy && composer.text.trim().length > 0
                    onClicked: sendMessage()
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 9
        visible: previewUrl !== ""
        color: "#f3f6f2"

        MouseArea { anchors.fill: parent }

        Row {
            id: previewBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: units.gu(1)
            spacing: units.gu(1)

            Button {
                text: "Back"
                onClicked: previewUrl = ""
            }
            Button {
                text: "Save to…"
                onClicked: {
                    openKind = ""
                    saveUrl = previewUrl
                }
            }
        }

        Image {
            id: previewImage
            anchors.top: previewBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: units.gu(1)
            source: previewUrl
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            fillMode: Image.PreserveAspectFit
        }

        Label {
            anchors.centerIn: previewImage
            visible: previewImage.status === Image.Error
            text: "This image could not be previewed."
        }
    }

    Loader {
        anchors.fill: parent
        z: 10
        active: saveUrl !== ""
        source: active ? "SaveFile.qml" : ""
        onLoaded: {
            item.fileUrl = saveUrl
            item.openKind = openKind
            item.closed.connect(function() { saveUrl = "" })
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                saveUrl = ""
                app.status = "File Manager export is unavailable."
            }
        }
    }

    Component {
        id: logoutDialog
        Dialog {
            id: confirmation
            title: "Sign out?"
            text: "This ends your Telegram session on this device."

            Button {
                text: "Sign out"
                color: app.accent
                onClicked: {
                    PopupUtils.close(confirmation)
                    request("logout", {}, function() {
                        chats = []
                        messages = []
                        activeChat = ""
                    })
                }
            }
            Button {
                text: "Cancel"
                onClicked: PopupUtils.close(confirmation)
            }
        }
    }
}
