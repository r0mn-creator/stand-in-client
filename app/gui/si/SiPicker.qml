import QtQuick
import QtQml
import QtQuick.Controls
import StandIn 1.0

// A row showing the current choice; activating it opens a menu of the options.
// options: [{ text: "…", value: … }, …]
SiRow {
    id: picker

    property var options: []
    property var currentValue
    signal activated(var value)

    chevron: true
    value: {
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === currentValue) {
                return options[i].text
            }
        }
        return ""
    }

    onClicked: menu.popup(picker, picker.width - menu.width - Theme.spaceSm, picker.height - 4)

    SiMenu {
        id: menu

        Instantiator {
            model: picker.options
            onObjectAdded: (index, object) => menu.insertItem(index, object)
            onObjectRemoved: (index, object) => menu.removeItem(object)

            SiMenuItem {
                text: modelData.text
                selected: modelData.value === picker.currentValue
                onTriggered: picker.activated(modelData.value)
            }
        }
    }
}
