import QtQuick 2.4
import QtQuick.Layouts 1.1
import Ubuntu.Components 1.3

ColumnLayout {
    id: pane
    property var files: []
    property bool transferring: false
    property bool busy: false
    property bool canScan: false
    property string chatTitle: ""
    signal openFile(string id)
    signal download(string id)
    signal cancel(string id)
    signal scan()
    signal save(string url)

    function size(bytes) {
        if (bytes < 1024)
            return bytes + " B"
        if (bytes < 1024 * 1024)
            return (bytes / 1024).toFixed(0) + " KB"
        if (bytes < 1024 * 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
    }

    spacing: units.gu(1)

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: units.gu(2)
        Layout.rightMargin: units.gu(2)
        text: pane.chatTitle === "" ? "Recent attachments and saved files" : pane.chatTitle
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font.pixelSize: units.gu(1.8)
        color: "#526860"
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: pane.files

        Text {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            visible: pane.files.length === 0 && !pane.busy
            text: pane.chatTitle === "" ? "Open a chat to find more files." : "No files in the messages loaded so far."
            wrapMode: Text.Wrap
            color: "#526860"
        }

        delegate: Rectangle {
            width: ListView.view.width
            height: Math.max(units.gu(8), detail.implicitHeight + units.gu(2))
            color: index % 2 === 0 ? "#ffffff" : "#f8faf8"

            RowLayout {
                anchors.fill: parent
                anchors.margins: units.gu(1)

                ColumnLayout {
                    id: detail
                    Layout.fillWidth: true
                    spacing: units.gu(0.32)

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: "#1b352d"
                        font.bold: true
                        font.pixelSize: units.gu(1.9)

                        MouseArea {
                            anchors.fill: parent
                            enabled: !pane.busy
                            onClicked: pane.openFile(modelData.id)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            var summary = modelData.kind
                            if (modelData.state === "downloading")
                                summary += " · " + pane.size(modelData.bytes)
                            if (modelData.size > 0)
                                summary += (modelData.state === "downloading" ? " / " : " · ") + pane.size(modelData.size)
                            if (modelData.state === "saved")
                                summary += " · Downloaded"
                            return summary
                        }
                        color: "#526860"
                        elide: Text.ElideRight
                        font.pixelSize: units.gu(1.55)
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!modelData.error
                        text: modelData.error || ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: "#943d26"
                        font.pixelSize: units.gu(1.45)
                    }
                }

                Button {
                    text: modelData.state === "saved" ? "Save to…" :
                          modelData.state === "downloading" ? "Cancel" :
                          modelData.error ? "Retry" : "Download"
                    enabled: !pane.busy && (modelData.state !== "available" || !pane.transferring)
                    onClicked: {
                        if (modelData.state === "saved")
                            pane.save(modelData.url)
                        else if (modelData.state === "downloading")
                            pane.cancel(modelData.id)
                        else
                            pane.download(modelData.id)
                    }
                }
            }
        }
    }

    Button {
        Layout.fillWidth: true
        Layout.leftMargin: units.gu(1)
        Layout.rightMargin: units.gu(1)
        Layout.bottomMargin: units.gu(1)
        visible: pane.canScan
        enabled: !pane.busy
        text: "Find files in older messages"
        onClicked: pane.scan()
    }
}
