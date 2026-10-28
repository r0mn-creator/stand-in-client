import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import UsbDevices 1.0
import StandIn 1.0
import "si"

// Stand-In: plug USB devices on this machine into the big PC
FocusScope {
    id: devicesPage
    objectName: qsTr("Devices")

    StackView.onActivated: {
        UsbDevices.refresh()
        targetPicker.forceActiveFocus(Qt.TabFocus)
    }

    function kindIcon(kind)
    {
        switch (kind) {
        case "input": return "gamepad"
        case "storage": return "drive"
        case "audio": return "speaker"
        case "video": return "camera"
        case "wireless": return "bluetooth"
        case "network": return "globe"
        case "test": return "flask"
        default: return "usb"
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight + Theme.spaceXl
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: column
            width: Math.min(Theme.sizeContentWidth, devicesPage.width - 2 * Theme.sizeGutter)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            // Which PC the devices go to
            SiGroup {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spaceXs

                SiPicker {
                    id: targetPicker
                    title: qsTr("Send to")
                    iconName: "tower"
                    enabled: UsbDevices.targets.length > 0
                    subtitle: UsbDevices.targets.length === 0 ? qsTr("Pair with a PC first") : ""
                    options: UsbDevices.targets.map(function(name, i) { return { text: name, value: i } })
                    currentValue: UsbDevices.targetIndex
                    onActivated: (value) => UsbDevices.targetIndex = value

                    KeyNavigation.down: deviceRepeater.count > 0 ? deviceRepeater.itemAt(0) : null

                    SiStatus {
                        visible: UsbDevices.targets.length > 0
                        text: UsbDevices.targetOnline ? qsTr("Online") : qsTr("Offline")
                        dotColor: UsbDevices.targetOnline ? Theme.statusAwake : Theme.statusOffline
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spaceSm
                Layout.leftMargin: Theme.spaceXxs
                Layout.rightMargin: Theme.spaceXxs
                text: qsTr("A device that's switched on is unplugged from this machine and plugged into your PC. Use it for wheels, flight sticks, pedals, drawing tablets and anything that needs its own driver on the PC.")
                font: Theme.label
                color: Theme.muted
                wrapMode: Text.Wrap
            }

            SiBanner {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spaceMd
                visible: UsbDevices.supported && UsbDevices.permissionProblem
                text: qsTr("Some devices are locked to this user. Run this once, then plug them in again:")
                command: UsbDevices.permissionFix
            }

            SiBanner {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spaceMd
                visible: !UsbDevices.supported
                text: qsTr("Sending USB devices from this platform is coming soon.")
            }

            SiSectionLabel {
                text: qsTr("On this machine")
                visible: deviceRepeater.count > 0
            }

            SiGroup {
                Layout.fillWidth: true
                visible: deviceRepeater.count > 0

                Repeater {
                    id: deviceRepeater
                    model: UsbDevices

                    SiRow {
                        title: model.name
                        subtitle: model.detail
                        iconName: devicesPage.kindIcon(model.kind)
                        iconColor: model.state === UsbDevices.Sending ? Theme.accent : Theme.muted
                        status: model.status
                        statusColor: model.state === UsbDevices.Sending ? Theme.accent
                                   : model.state === UsbDevices.Failed ? Theme.warning
                                   : Theme.muted
                        interactive: sendSwitch.enabled

                        onClicked: if (sendSwitch.enabled) UsbDevices.setForwarding(index, !model.forwarding)

                        KeyNavigation.up: index > 0 ? deviceRepeater.itemAt(index - 1) : targetPicker
                        KeyNavigation.down: index < deviceRepeater.count - 1 ? deviceRepeater.itemAt(index + 1) : null

                        SiSpinner {
                            visible: model.state === UsbDevices.Connecting
                            size: 18
                        }

                        SiSwitch {
                            id: sendSwitch
                            checked: model.forwarding
                            // A device that can't be sent can still be switched off
                            enabled: model.canSend || model.forwarding
                            onToggled: UsbDevices.setForwarding(index, checked)
                        }
                    }
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spaceXl
                visible: UsbDevices.supported && deviceRepeater.count === 0
                text: qsTr("No USB devices found")
                font: Theme.body
                color: Theme.muted
            }
        }
    }
}
