import QtQuick 2.4

Rectangle {
    id: tile
    property string label: ""
    property real sizing: 1
    property bool primary: false
    signal activated()
    radius: 4 * sizing
    color: primary ? (area.pressed ? "#a85b37" : "#cf8c54") :
                     (area.pressed ? "#51452e" : "#26251d")
    border.color: primary ? "#eeb37b" : "#76684c"
    border.width: 1
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: activated()

    Text {
        anchors.centerIn: parent
        text: tile.label
        color: tile.primary ? "#17140e" : "#f4e6ca"
        font.bold: true
        font.pixelSize: 16 * sizing
    }
    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: tile.activated()
    }
}
