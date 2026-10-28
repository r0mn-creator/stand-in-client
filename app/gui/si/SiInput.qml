import QtQuick
import QtQuick.Controls
import StandIn 1.0

TextField {
    id: field

    property bool error: false

    implicitHeight: Theme.sizeInput
    leftPadding: Theme.spaceMd
    rightPadding: Theme.spaceMd
    font: Theme.body
    color: Theme.text
    placeholderTextColor: Theme.subtle
    selectionColor: Theme.accent
    selectedTextColor: Theme.textOnAccent
    selectByMouse: true

    background: Rectangle {
        radius: Theme.radiusSm
        color: Theme.raised
        border.width: field.activeFocus || field.error ? 2 : 1
        border.color: field.error ? Theme.danger : field.activeFocus ? Theme.accent : Theme.borderStrong
    }
}
