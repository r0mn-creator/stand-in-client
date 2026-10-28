import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StandIn 1.0

// Title, plain-words body, optional content, buttons bottom-right (secondary then primary)
Popup {
    id: dialog

    property string title
    property string text
    default property alias content: contentColumn.data
    property alias buttons: buttonRow.data


    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(Theme.sizeDialogWidth, parent ? parent.width * 0.9 : Theme.sizeDialogWidth)
    modal: true
    focus: true
    padding: 28
    closePolicy: Popup.CloseOnEscape

    onClosed: {
        // Hand focus back so keyboard and gamepad navigation keep working
        if (typeof stackView !== "undefined") {
            stackView.forceActiveFocus()
        }
    }

    Overlay.modal: Rectangle {
        color: Theme.scrim
        Behavior on opacity { NumberAnimation { duration: Theme.motionNormal } }
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

    contentItem: ColumnLayout {
        spacing: 0

        Label {
            Layout.fillWidth: true
            text: dialog.title
            font: Theme.title
            color: Theme.text
            wrapMode: Text.Wrap
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceXs
            visible: text !== ""
            text: dialog.text
            font: Theme.body
            color: Theme.muted
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.topMargin: children.length > 0 ? Theme.spaceLg : 0
            spacing: Theme.spaceSm
        }

        RowLayout {
            id: buttonRow
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Theme.spaceLg
            spacing: Theme.spaceSm
        }
    }
}
