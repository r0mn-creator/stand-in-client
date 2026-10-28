import QtQuick
import QtQuick.Controls
import StandIn 1.0

Rectangle {
    property alias text: pillText.text

    implicitWidth: pillText.implicitWidth + 20
    implicitHeight: 24
    radius: 12
    color: Theme.raised
    border.width: 1
    border.color: Theme.border

    Label {
        id: pillText
        anchors.centerIn: parent
        font: Theme.caption
        color: Theme.muted
    }
}
