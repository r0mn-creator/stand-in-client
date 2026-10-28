import QtQuick
import QtQuick.Controls
import StandIn 1.0

// 44×44 square button with one icon; the tooltip names what it does
AbstractButton {
    id: button

    property string iconName
    property string tip
    property bool flat: false

    implicitWidth: Theme.sizeIconButton
    implicitHeight: Theme.sizeIconButton
    focusPolicy: Qt.StrongFocus

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    contentItem: Item {
        SiIcon {
            anchors.centerIn: parent
            glyph: button.iconName
            color: button.enabled ? Theme.text : Theme.subtle
        }
    }

    background: Rectangle {
        radius: Theme.radiusSm
        color: button.down ? Theme.border : (button.hovered ? Theme.raised : (button.flat ? "transparent" : Theme.surface))
        border.width: button.flat ? 0 : 1
        border.color: Theme.border

        Behavior on color { ColorAnimation { duration: Theme.motionFast } }

        SiFocusRing { target: button; ringRadius: Theme.radiusSm }
    }

    SiToolTip {
        visible: button.hovered && button.tip !== ""
        text: button.tip
        y: button.height + 6
    }
}
