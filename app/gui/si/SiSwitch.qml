import QtQuick
import QtQuick.Controls
import StandIn 1.0

Switch {
    id: control

    padding: 0
    spacing: 0
    implicitWidth: 44
    implicitHeight: 26
    focusPolicy: Qt.NoFocus

    indicator: Rectangle {
        implicitWidth: 44
        implicitHeight: 26
        x: control.leftPadding
        y: (control.height - height) / 2
        radius: height / 2
        color: control.checked ? (control.enabled ? Theme.accent : Theme.accentSoft) : Theme.raised
        border.width: control.checked ? 0 : 1
        border.color: Theme.borderStrong
        opacity: control.enabled ? 1 : 0.5

        Behavior on color { ColorAnimation { duration: Theme.motionFast } }

        Rectangle {
            width: 20
            height: 20
            radius: 10
            y: 3
            x: control.checked ? parent.width - width - 3 : 3
            color: control.checked ? Theme.textOnAccent : Theme.muted

            Behavior on x { NumberAnimation { duration: Theme.motionFast; easing.type: Easing.OutCubic } }
        }
    }

    contentItem: Item {}
}
