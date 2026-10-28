import QtQuick
import QtQuick.Controls
import StandIn 1.0

// Status dot and words: "Awake", "Not paired", "Offline"…
Row {
    property alias text: statusText.text
    property color dotColor: Theme.statusAwake
    property bool checking: false
    property alias font: statusText.font
    property alias textColor: statusText.color

    spacing: 6

    Item {
        width: Theme.sizeStatusDot
        height: statusText.height

        Rectangle {
            anchors.centerIn: parent
            visible: !checking
            width: Theme.sizeStatusDot
            height: Theme.sizeStatusDot
            radius: width / 2
            color: dotColor
        }

        SiSpinner {
            anchors.centerIn: parent
            visible: checking
            size: 12
            color: Theme.muted
        }
    }

    Label {
        id: statusText
        font: Theme.caption
        color: Theme.muted
    }
}
