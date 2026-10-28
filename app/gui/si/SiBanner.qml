import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StandIn 1.0

// Needs-attention notice; an optional command is shown selectable for copying
Rectangle {
    id: banner

    property string text
    property string command

    implicitHeight: layout.implicitHeight + 2 * Theme.spaceMd
    radius: Theme.radiusMd
    color: Theme.warningSoft
    border.width: 1
    border.color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.3)

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceSm

        SiIcon {
            Layout.alignment: Qt.AlignTop
            glyph: "warning"
            color: Theme.warning
            sourceSize: Qt.size(Theme.sizeIconSmall, Theme.sizeIconSmall)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceXs

            Label {
                Layout.fillWidth: true
                text: banner.text
                font: Theme.body
                color: Theme.text
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                visible: banner.command !== ""
                implicitHeight: commandText.implicitHeight + 16
                radius: Theme.radiusXs
                color: Theme.raised

                TextEdit {
                    id: commandText
                    anchors.fill: parent
                    anchors.margins: 8
                    readOnly: true
                    selectByMouse: true
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.PlainText
                    text: banner.command
                    font.family: "monospace"
                    font.pixelSize: 12
                    color: Theme.text
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.textOnAccent
                }
            }
        }
    }
}
