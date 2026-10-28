import QtQuick
import QtQuick.Controls
import StandIn 1.0

// A small PC card in the row under the hero card
AbstractButton {
    id: tile

    property string name
    property string status
    property color statusColor: Theme.statusAwake
    property bool checking: false
    property bool selected: false

    implicitWidth: Theme.sizeTileWidth
    implicitHeight: Theme.sizeTileHeight
    focusPolicy: Qt.StrongFocus
    padding: Theme.spaceSm

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    contentItem: Item {
        SiIcon {
            anchors.left: parent.left
            anchors.top: parent.top
            glyph: "tower"
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 2

            Label {
                width: parent.width
                text: tile.name
                font: Theme.bodyStrong
                color: Theme.text
                elide: Text.ElideRight
            }

            SiStatus {
                text: tile.status
                dotColor: tile.statusColor
                checking: tile.checking
            }
        }
    }

    background: Rectangle {
        radius: Theme.radiusMd
        color: tile.selected || tile.hovered ? Theme.raised : Theme.surface
        border.width: tile.selected ? 2 : 1
        border.color: tile.selected ? Theme.accent : Theme.border

        Behavior on color { ColorAnimation { duration: Theme.motionFast } }

        SiFocusRing { target: tile; ringRadius: Theme.radiusMd }
    }
}
