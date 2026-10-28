import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StandIn 1.0

// One line in a group: optional icon, title, subtitle, and one trailing control
AbstractButton {
    id: row

    property string title
    property string subtitle
    property string iconName
    property color iconColor: Theme.muted
    property string value
    property bool chevron: false
    property bool interactive: chevron || value !== ""
    property string status
    property color statusColor: Theme.muted
    default property alias trailing: trailingSlot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(subtitle || status ? Theme.sizeRowWithSubtitle : Theme.sizeRow,
                             layout.implicitHeight + 2 * Theme.spaceSm)
    focusPolicy: Qt.StrongFocus
    hoverEnabled: interactive

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    contentItem: Item {}

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Theme.radiusLg - 1
            color: row.interactive && (row.hovered || row.down) ? Theme.raised : "transparent"
        }

        // Separator from the row above
        Rectangle {
            visible: row.y > 0
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spaceMd
            height: 1
            color: Theme.border
        }

        SiFocusRing {
            target: row
            anchors.margins: 2
            ringRadius: Theme.radiusSm
        }
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        spacing: Theme.spaceSm

        Rectangle {
            visible: row.iconName !== ""
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 18
            color: Theme.raised

            SiIcon {
                anchors.centerIn: parent
                glyph: row.iconName
                color: row.iconColor
                sourceSize: Qt.size(Theme.sizeIconSmall, Theme.sizeIconSmall)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceSm
            Layout.bottomMargin: Theme.spaceSm
            spacing: 2

            Label {
                Layout.fillWidth: true
                text: row.title
                font: Theme.bodyStrong
                color: row.enabled ? Theme.text : Theme.subtle
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.subtitle
                font: Theme.label
                color: Theme.muted
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.status
                font: Theme.caption
                color: row.statusColor
                wrapMode: Text.Wrap
            }
        }

        Label {
            visible: row.value !== ""
            text: row.value
            font: Theme.body
            color: Theme.muted
        }

        RowLayout {
            id: trailingSlot
            spacing: Theme.spaceSm
            visible: implicitWidth > 0
        }

        SiIcon {
            visible: row.chevron
            glyph: "chevron-right"
            color: Theme.subtle
            sourceSize: Qt.size(Theme.sizeIconSmall, Theme.sizeIconSmall)
        }
    }
}
