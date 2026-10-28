import QtQuick
import QtQuick.Controls
import StandIn 1.0
import "si"

ItemDelegate {
    property GridView grid

    highlighted: grid.activeFocus && grid.currentItem === this

    // The focused card grows a little and gets the focus ring
    scale: highlighted && InputMode.keyboard ? 1.04 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.motionFast; easing.type: Easing.OutCubic } }

    background: Rectangle {
        radius: Theme.radiusMd
        color: parent.hovered ? Theme.surface : "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: "transparent"
            border.width: Theme.sizeFocusRing
            border.color: Theme.accentHover
            visible: parent.parent.highlighted && InputMode.keyboard
        }
    }

    Keys.onLeftPressed: {
        grid.moveCurrentIndexLeft()
    }
    Keys.onRightPressed: {
        grid.moveCurrentIndexRight()
    }
    Keys.onDownPressed: {
        grid.moveCurrentIndexDown()
    }
    Keys.onUpPressed: {
        grid.moveCurrentIndexUp()

        // If we've reached the top of the grid, move focus to the toolbar
        if (grid.currentItem === this) {
            nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
        }
    }
    Keys.onReturnPressed: {
        clicked()
    }
    Keys.onEnterPressed: {
        clicked()
    }
}
