import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2

import UsbDevices 1.0

// Stand-In: plug USB devices on this machine into the big PC
Item {
    id: devicesPage
    objectName: qsTr("Devices")

    StackView.onActivated: {
        UsbDevices.refresh()
        deviceList.forceActiveFocus()
    }

    Label {
        anchors.centerIn: parent
        visible: !UsbDevices.supported
        text: qsTr("Sending USB devices isn't available on this platform yet.")
        font.pointSize: 16
        color: "#98A2B3"
    }

    ColumnLayout {
        visible: UsbDevices.supported
        anchors.fill: parent
        anchors.margins: 20
        anchors.topMargin: 10
        spacing: 12

        // Which PC the devices go to
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: qsTr("Send to")
                font.pointSize: 13
            }

            ComboBox {
                id: targetBox
                implicitWidth: 260
                model: UsbDevices.targets
                currentIndex: UsbDevices.targetIndex
                enabled: count > 1
                onActivated: UsbDevices.targetIndex = currentIndex
            }

            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: UsbDevices.targetOnline ? "#4ADE80" : "#64748B"
                visible: targetBox.count > 0
            }

            Label {
                text: targetBox.count === 0 ? qsTr("Pair with a PC first")
                                            : UsbDevices.targetOnline ? qsTr("Online") : qsTr("Offline")
                color: "#98A2B3"
                font.pointSize: 11
            }

            Item { Layout.fillWidth: true }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: "#98A2B3"
            font.pointSize: 11
            text: qsTr("A device that's switched on is unplugged from this machine and plugged into the PC, as if it were connected there. Use this for wheels, flight sticks, pedals, drawing tablets and anything else the PC needs its own driver or software for. Your choices are remembered.")
        }

        // Shown when Linux won't let this user open some devices
        Rectangle {
            Layout.fillWidth: true
            visible: UsbDevices.permissionProblem
            implicitHeight: permissionText.implicitHeight + 20
            radius: 8
            color: "#2A2416"
            border.color: "#5C4A1A"

            // Selectable, so the command can be copied
            TextEdit {
                id: permissionText
                anchors.fill: parent
                anchors.margins: 10
                readOnly: true
                selectByMouse: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font.pointSize: 11
                color: "#FCD34D"
                selectionColor: "#5C4A1A"
                text: qsTr("Some devices are locked to this user. Install Stand-In's USB access rule once, then replug them:") +
                      "\n    " + UsbDevices.permissionFix
            }
        }

        ListView {
            id: deviceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: UsbDevices
            keyNavigationEnabled: true
            highlightFollowsCurrentItem: false

            ScrollBar.vertical: ScrollBar {}

            Label {
                anchors.centerIn: parent
                visible: deviceList.count === 0
                text: qsTr("No USB devices found")
                color: "#98A2B3"
                font.pointSize: 14
            }

            Keys.onReturnPressed: currentItem.toggle()
            Keys.onEnterPressed: currentItem.toggle()
            Keys.onSpacePressed: currentItem.toggle()

            delegate: Rectangle {
                id: card
                width: deviceList.width - 12
                implicitHeight: cardRow.implicitHeight + 24
                radius: 10
                color: "#1A2029"
                border.width: deviceList.activeFocus && ListView.isCurrentItem ? 2 : 1
                border.color: deviceList.activeFocus && ListView.isCurrentItem ? "#60A5FA" : "#2C3542"

                function toggle() {
                    if (sendSwitch.enabled) {
                        UsbDevices.setForwarding(index, !model.forwarding)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        deviceList.currentIndex = index
                        deviceList.forceActiveFocus()
                    }
                }

                RowLayout {
                    id: cardRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 14

                    // What kind of device this is, at a glance
                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: "#222A35"

                        Label {
                            anchors.centerIn: parent
                            font.pointSize: 9
                            font.bold: true
                            color: "#98A2B3"
                            text: {
                                switch (model.kind) {
                                case "input": return qsTr("INPUT")
                                case "storage": return qsTr("DISK")
                                case "audio": return qsTr("AUDIO")
                                case "video": return qsTr("CAM")
                                case "wireless": return qsTr("RADIO")
                                case "network": return qsTr("NET")
                                case "test": return qsTr("TEST")
                                default: return qsTr("USB")
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: model.name
                            font.pointSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: model.detail
                            font.pointSize: 10
                            color: "#98A2B3"
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: model.status
                            font.pointSize: 10
                            wrapMode: Text.Wrap
                            color: {
                                switch (model.state) {
                                case UsbDevices.Sending: return "#4ADE80"
                                case UsbDevices.Failed: return "#FBBF24"
                                default: return "#7C8798"
                                }
                            }
                        }
                    }

                    BusyIndicator {
                        implicitWidth: 28
                        implicitHeight: 28
                        running: model.state === UsbDevices.Connecting
                        visible: running
                    }

                    Switch {
                        id: sendSwitch
                        checked: model.forwarding
                        // A device that can't be sent can still be switched off
                        enabled: model.canSend || model.forwarding
                        focusPolicy: Qt.NoFocus
                        onToggled: UsbDevices.setForwarding(index, checked)

                        ToolTip.delay: 1000
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Send to %1").arg(targetBox.currentText)
                    }
                }
            }
        }
    }
}
