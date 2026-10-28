import QtQuick
import QtQuick.Controls
import StandIn 1.0
import "si"

// Every stock dialog in the app, drawn as a Stand-In dialog
Dialog {
    id: dialog

    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(Theme.sizeDialogWidth, Overlay.overlay ? Overlay.overlay.width * 0.9 : Theme.sizeDialogWidth)
    padding: 28
    topPadding: title !== "" ? Theme.spaceXs : 28
    bottomPadding: 0

    onClosed: {
        // We must force focus back to the last item. If we don't,
        // gamepad and keyboard navigation will break after a
        // dialog appears.
        stackView.forceActiveFocus()
    }

    Overlay.modal: Rectangle {
        color: Theme.scrim
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motionNormal; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.motionNormal; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motionFast }
    }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radiusXl
        border.width: 1
        border.color: Theme.border
    }

    header: Label {
        visible: dialog.title !== ""
        text: dialog.title
        font: Theme.title
        color: Theme.text
        wrapMode: Text.Wrap
        leftPadding: 28
        rightPadding: 28
        topPadding: 28
    }

    footer: DialogButtonBox {
        id: buttonBox
        standardButtons: dialog.standardButtons
        alignment: Qt.AlignRight
        spacing: Theme.spaceSm
        padding: 28
        topPadding: Theme.spaceLg
        visible: count > 0

        background: Item {}

        delegate: SiButton {
            kind: {
                switch (DialogButtonBox.buttonRole) {
                case DialogButtonBox.AcceptRole:
                case DialogButtonBox.YesRole:
                case DialogButtonBox.ApplyRole:
                    return "primary"
                case DialogButtonBox.HelpRole:
                    return "text"
                case DialogButtonBox.DestructiveRole:
                    return "danger"
                default:
                    return "secondary"
                }
            }

            Keys.onRightPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocus)
            Keys.onLeftPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
        }
    }
}
