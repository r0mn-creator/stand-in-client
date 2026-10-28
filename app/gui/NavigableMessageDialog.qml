import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StandIn 1.0
import "si"

NavigableDialog {
    id: dialog

    property alias text: dialogLabel.dialogText
    property alias showSpinner: dialogSpinner.visible
    // Kept so older callers still work; Stand-In dialogs don't show icons
    property string imageSrc

    property string helpText
    property string helpUrl
    property string helpTextSeparator : " "

    onOpened: {
        // Put focus on the last (primary) button so Enter does the expected thing
        if (footer && footer.count > 0) {
            footer.itemAt(footer.count - 1).forceActiveFocus(Qt.TabFocus)
        }
    }

    onHelpRequested: {
        Qt.openUrlExternally(helpUrl)
        close()
    }

    RowLayout {
        width: parent.width
        spacing: Theme.spaceSm

        SiSpinner {
            id: dialogSpinner
            Layout.alignment: Qt.AlignTop
            visible: false
        }

        Label {
            property string dialogText

            id: dialogLabel
            Layout.fillWidth: true
            text: dialogText + ((helpText && (standardButtons & Dialog.Help)) ? (helpTextSeparator + helpText) : "")
            font: dialog.title !== "" ? Theme.body : Theme.headline
            color: dialog.title !== "" ? Theme.muted : Theme.text
            wrapMode: Text.Wrap
            elide: Label.ElideRight
            Layout.maximumHeight: 400
        }
    }
}
