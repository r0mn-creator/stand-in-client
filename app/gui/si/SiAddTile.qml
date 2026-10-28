import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import StandIn 1.0

// Same size as a PC tile, dashed, always last in the row
AbstractButton {
    id: tile

    implicitWidth: Theme.sizeTileWidth
    implicitHeight: Theme.sizeTileHeight
    focusPolicy: Qt.StrongFocus

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    contentItem: Item {
        Column {
            anchors.centerIn: parent
            spacing: 4

            SiIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                glyph: "plus"
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.text
                font: Theme.caption
                color: Theme.muted
            }
        }
    }

    background: Item {
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: tile.hovered ? Theme.surface : "transparent"
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.borderStrong
                strokeWidth: 1
                strokeStyle: ShapePath.DashLine
                dashPattern: [6, 4]
                fillColor: "transparent"

                PathRectangle {
                    x: 0.5
                    y: 0.5
                    width: tile.width - 1
                    height: tile.height - 1
                    radius: Theme.radiusMd
                }
            }
        }

        SiFocusRing { target: tile; ringRadius: Theme.radiusMd }
    }
}
