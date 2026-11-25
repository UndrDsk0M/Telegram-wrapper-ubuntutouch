import QtQuick 2.4
import Ubuntu.Components 1.3
import Ubuntu.Content 1.3

Rectangle {
    id: sheet
    color: "#f3f6f2"
    property string fileUrl: ""
    property var transfer: null
    signal closed()

    function sendFile() {
        if (!transfer)
            return
        if (transfer.state === ContentTransfer.InProgress) {
            transfer.items = [contentItem.createObject(sheet, { "url": fileUrl })]
            transfer.state = ContentTransfer.Charged
            closed()
        } else if (transfer.state === ContentTransfer.Aborted) {
            transfer = null
        }
    }

    Button {
        id: closeButton
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: units.gu(1)
        text: "Back"
        onClicked: sheet.closed()
    }

    ContentPeerPicker {
        anchors.top: closeButton.bottom
        anchors.topMargin: units.gu(1)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentType: ContentType.All
        handler: ContentHandler.Destination
        onPeerSelected: {
            sheet.transfer = peer.request()
            sheet.sendFile()
        }
        onCancelPressed: sheet.closed()
    }

    Connections {
        target: sheet.transfer
        onStateChanged: sheet.sendFile()
    }

    Component {
        id: contentItem
        ContentItem {}
    }
}
