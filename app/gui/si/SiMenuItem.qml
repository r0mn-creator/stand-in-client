import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StandIn 1.0

MenuItem {
    id: item

    property string iconName
    property bool danger: false
    property bool selected: false

    implicitHeight: visible ? 44 : 0
    leftPadding: Theme.spaceSm
    rightPadding: Theme.spaceSm
    font: Theme.body

    Keys.onReturnPressed: triggered()
    Keys.onEnterPressed: triggered()

    contentItem: RowLayout {
        spacing: Theme.spaceSm

        SiIcon {
            visible: item.iconName !== ""
            glyph: item.iconName
            color: item.danger ? Theme.danger : Theme.muted
            sourceSize: Qt.size(Theme.sizeIconSmall, Theme.sizeIconSmall)
        }

        Label {
            Layout.fillWidth: true
            text: item.text
            font: item.font
            color: !item.enabled ? Theme.subtle : item.danger ? Theme.danger : Theme.text
            elide: Text.ElideRight
        }

        SiIcon {
            visible: item.selected
            glyph: "check"
            color: Theme.accent
            sourceSize: Qt.size(Theme.sizeIconSmall, Theme.sizeIconSmall)
        }
    }

    indicator: Item {}
    arrow: Item {}

    background: Rectangle {
        radius: Theme.radiusSm
        color: item.highlighted || item.hovered ? Theme.raised : "transparent"
    }
}
