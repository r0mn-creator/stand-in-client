import QtQuick
import QtQuick.Layouts
import StandIn 1.0

// A rounded card holding rows; rows draw the separators between them
Rectangle {
    default property alias rows: column.data

    implicitHeight: column.implicitHeight
    color: Theme.surface
    radius: Theme.radiusLg
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
    }
}
