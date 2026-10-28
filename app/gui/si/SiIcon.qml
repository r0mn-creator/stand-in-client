import QtQuick
import QtQuick.Controls.impl
import StandIn 1.0

// A line icon from the shared set, tinted
IconImage {
    property string glyph

    source: glyph ? Theme.icon(glyph) : ""
    sourceSize: Qt.size(Theme.sizeIcon, Theme.sizeIcon)
    color: Theme.text
}
