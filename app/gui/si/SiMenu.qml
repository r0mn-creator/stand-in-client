import QtQuick
import QtQuick.Controls
import StandIn 1.0

Menu {
    id: menu

    padding: 6
    implicitWidth: 240

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motionNormal; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motionFast }
    }

    background: Rectangle {
        implicitWidth: 240
        color: Theme.surface
        radius: Theme.radiusMd
        border.width: 1
        border.color: Theme.border
    }

    delegate: SiMenuItem {}
}
