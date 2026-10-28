import QtQuick
import QtQuick.Controls
import StandIn 1.0

// Capsule button. kind: "primary" (one per screen), "secondary", "danger", "text"
AbstractButton {
    id: button

    property string kind: "primary"
    property bool large: false
    property bool busy: false

    readonly property bool isPrimary: kind === "primary"

    implicitHeight: large ? Theme.sizeButtonLarge : Theme.sizeButton
    implicitWidth: Math.max(kind === "text" ? 0 : 120, label.implicitWidth + (kind === "text" ? 16 : 48))
    focusPolicy: Qt.StrongFocus
    font: Theme.button

    Keys.onReturnPressed: if (enabled) clicked()
    Keys.onEnterPressed: if (enabled) clicked()

    contentItem: Item {
        Label {
            id: label
            anchors.centerIn: parent
            visible: !button.busy
            text: button.text
            font: button.font
            color: !button.enabled ? Theme.subtle
                 : button.isPrimary ? Theme.textOnAccent
                 : button.kind === "danger" ? Theme.danger
                 : button.kind === "text" ? Theme.accent
                 : Theme.text
        }

        SiSpinner {
            anchors.centerIn: parent
            visible: button.busy
            size: 20
            color: button.isPrimary ? Theme.textOnAccent : Theme.accent
        }
    }

    background: Rectangle {
        radius: height / 2
        color: {
            if (button.kind === "text") {
                return button.hovered ? Theme.raised : "transparent"
            }
            if (!button.enabled) {
                return Theme.raised
            }
            if (button.isPrimary) {
                return (button.down || button.hovered) ? Theme.accentHover : Theme.accent
            }
            return button.down ? Theme.border : (button.hovered ? Theme.borderStrong : Theme.raised)
        }
        border.width: (button.isPrimary || button.kind === "text") ? 0 : 1
        border.color: Theme.border

        Behavior on color { ColorAnimation { duration: Theme.motionFast } }

        SiFocusRing { target: button; ringRadius: height / 2 }
    }
}
