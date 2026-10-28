import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StandIn 1.0

// Title and current value on one line, the slider below
Item {
    id: sliderRow

    property string title
    property string valueText
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias value: slider.value
    signal moved()

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 2 * Theme.spaceSm

    Rectangle {
        visible: sliderRow.y > 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spaceMd
        height: 1
        color: Theme.border
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Theme.spaceMd
        anchors.topMargin: Theme.spaceSm
        anchors.bottomMargin: Theme.spaceSm
        spacing: Theme.spaceXs

        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: sliderRow.title
                font: Theme.bodyStrong
                color: Theme.text
            }

            Label {
                text: sliderRow.valueText
                font: Theme.body
                color: Theme.muted
            }
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            onMoved: sliderRow.moved()

            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Theme.raised

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                }
            }

            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: 20
                height: 20
                radius: 10
                color: Theme.text
                border.width: slider.activeFocus && InputMode.keyboard ? 2 : 0
                border.color: Theme.accentHover
            }
        }
    }
}
