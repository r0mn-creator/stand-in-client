import QtQuick
import QtQuick.Controls
import StandIn 1.0

ToolTip {
    id: tip

    delay: 600
    padding: Theme.spaceXs
    leftPadding: Theme.spaceSm
    rightPadding: Theme.spaceSm

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motionFast }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motionFast }
    }

    contentItem: Label {
        text: tip.text
        font: Theme.caption
        color: Theme.text
    }

    background: Rectangle {
        color: Theme.raised
        radius: Theme.radiusXs
        border.width: 1
        border.color: Theme.border
    }
}
