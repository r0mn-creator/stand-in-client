import QtQuick
import StandIn 1.0

// The keyboard/gamepad focus ring; follows its parent's shape
Rectangle {
    property Item target: parent
    property real ringRadius: 0

    anchors.fill: parent
    radius: ringRadius
    color: "transparent"
    border.width: Theme.sizeFocusRing
    border.color: Theme.accentHover
    visible: target.activeFocus && InputMode.keyboard
}
