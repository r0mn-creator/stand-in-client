import QtQuick
import StandIn 1.0

// A row whose whole surface flips its switch
SiRow {
    id: row

    property bool isOn
    signal flipped(bool on)

    interactive: enabled
    onClicked: if (enabled) flipped(!isOn)

    SiSwitch {
        checked: row.isOn
        enabled: row.enabled
        onToggled: {
            row.flipped(checked)
            // Keep following the setting rather than the click
            checked = Qt.binding(function() { return row.isOn })
        }
    }
}
