import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2
import QtQuick.Controls.Material 2.2

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import UsbDevices 1.0
import StandIn 1.0
import "si"

ApplicationWindow {
    property bool pollingActive: false

    // Set by SettingsView to force the back operation to pop all
    // pages except the initial view. This is required when doing
    // a retranslate() because AppView breaks for some reason.
    property bool clearOnBack: false

    id: window
    width: 1280
    height: 800
    minimumWidth: 640
    minimumHeight: 480
    color: Theme.ground
    font: Theme.body

    Material.theme: Material.Dark
    Material.accent: Theme.accent
    Material.background: Theme.ground
    Material.foreground: Theme.text

    // This function runs prior to creation of the initial StackView item
    function doEarlyInit() {
        // Override the background color to Material 2 colors for Qt 6.5+
        // in order to improve contrast between GFE's placeholder box art
        // and the background of the app grid.

        SdlGamepadKeyNavigation.enable()

        // Devices the user chose to send start going as soon as their PC is online
        UsbDevices.initialize(ComputerManager)
    }

    Component.onCompleted: {

        // Show the window according to the user's preferences
        if (SystemProperties.hasDesktopEnvironment) {
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED) {
                window.showMaximized()
            }
            else if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_FULLSCREEN) {
                window.showFullScreen()
            }
            else {
                window.show()
            }
        } else {
            window.showFullScreen()
        }

        // Display any modal dialogs for configuration warnings
        if (isGuiLaunch) {
            if (SystemProperties.isWow64) {
                wow64Dialog.open()
            }

            // Hardware acceleration and unmapped gamepads are checked asynchronously
            SystemProperties.hasHardwareAccelerationChanged.connect(hasHardwareAccelerationChanged)
            SystemProperties.unmappedGamepadsChanged.connect(hasUnmappedGamepadsChanged)
            SystemProperties.startAsyncLoad()
        }
    }

    function hasHardwareAccelerationChanged() {
        if (!SystemProperties.hasHardwareAcceleration && StreamingPreferences.videoDecoderSelection !== StreamingPreferences.VDS_FORCE_SOFTWARE) {
            if (SystemProperties.isRunningXWayland) {
                xWaylandDialog.open()
            }
            else {
                noHwDecoderDialog.open()
            }
        }
    }

    function hasUnmappedGamepadsChanged() {
        if (SystemProperties.unmappedGamepads) {
            unmappedGamepadDialog.unmappedGamepads = SystemProperties.unmappedGamepads
            unmappedGamepadDialog.open()
        }
    }

    // It would be better to use TextMetrics here, but it always lays out
    // the text slightly more compactly than real Text does in ToolTip,
    // causing unexpected line breaks to be inserted
    Text {
        id: tooltipTextLayoutHelper
        visible: false
        font: ToolTip.toolTip.font
        text: ToolTip.toolTip.text
    }

    // This configures the maximum width of the singleton attached QML ToolTip. If left unconstrained,
    // it will never insert a line break and just extend on forever.
    ToolTip.toolTip.contentWidth: Math.min(tooltipTextLayoutHelper.width, 400)

    function goBack() {
        if (clearOnBack) {
            // Pop all items except the first one
            stackView.pop(null)
            clearOnBack = false
        }
        else {
            stackView.pop()
        }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        focus: true

        Component.onCompleted: {
            // Perform our early initialization before constructing
            // the initial view and pushing it to the StackView
            doEarlyInit()
            push(initialView)
        }

        onCurrentItemChanged: {
            // Ensure focus travels to the next view when going back
            if (currentItem) {
                currentItem.forceActiveFocus()
            }
        }

        Keys.onEscapePressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onBackPressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onMenuPressed: {
            settingsButton.clicked()
        }

        // This is a keypress we've reserved for letting the
        // SdlGamepadKeyNavigation object tell us to show settings
        // when Menu is consumed by a focused control.
        Keys.onHangupPressed: {
            settingsButton.clicked()
        }
    }

    // This timer keeps us polling for 5 minutes of inactivity
    // to allow the user to work with Stand-In on a second display
    // while dealing with configuration issues. This will ensure
    // machines come online even if the input focus isn't on Stand-In.
    Timer {
        id: inactivityTimer
        interval: 5 * 60000
        onTriggered: {
            if (!active && pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
    }

    onVisibleChanged: {
        // Polling is only managed from the window for a normal GUI launch;
        // CLI commands (stream/quit/pair) manage it via the ComputerSeeker.
        if (isGuiLaunch) {
            // When we become invisible while streaming is going on,
            // stop polling immediately.
            if (!visible) {
                inactivityTimer.stop()

                if (pollingActive) {
                    ComputerManager.stopPollingAsync()
                    pollingActive = false
                }
            }
            else if (active) {
                // When we become visible and active again, start polling
                inactivityTimer.stop()

                // Restart polling if it was stopped
                if (!pollingActive) {
                    ComputerManager.startPolling()
                    pollingActive = true
                }
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        // Polling is only managed from the window for a normal GUI launch;
        // CLI commands (stream/quit/pair) manage it via the ComputerSeeker.
        if (isGuiLaunch) {
            if (active) {
                // Stop the inactivity timer
                inactivityTimer.stop()

                // Restart polling if it was stopped
                if (!pollingActive) {
                    ComputerManager.startPolling()
                    pollingActive = true
                }
            }
            else {
                // Start the inactivity timer to stop polling
                // if focus does not return within a few minutes.
                inactivityTimer.restart()
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    function navigateTo(url, objectType)
    {
        var existingItem = stackView.find(function(item, index) {
            return item instanceof objectType
        })

        if (existingItem !== null) {
            // Pop to the existing item
            stackView.pop(existingItem)
        }
        else {
            // Create a new item
            stackView.push(url)
        }
    }

    // Home: logo, name and version on the left, Devices and Settings on the right.
    // Sub-pages: back and the page title.
    header: Rectangle {
        id: toolBar
        height: Theme.sizeHeaderHeight + Theme.spaceSm
        color: Theme.ground

        readonly property bool home: stackView.depth <= 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.sizeGutter
            anchors.rightMargin: Theme.sizeGutter
            anchors.topMargin: Theme.spaceSm
            spacing: Theme.spaceSm

            SiIconButton {
                id: backButton
                visible: !toolBar.home
                iconName: "back"
                tip: qsTr("Back")
                onClicked: goBack()

                Keys.onDownPressed: stackView.currentItem.forceActiveFocus(Qt.TabFocus)
            }

            Image {
                visible: toolBar.home
                source: "qrc:/res/stand-in.svg"
                sourceSize: Qt.size(Theme.sizeLogo * 2, Theme.sizeLogo * 2)
                Layout.preferredWidth: Theme.sizeLogo
                Layout.preferredHeight: Theme.sizeLogo
            }

            Label {
                text: toolBar.home ? "Stand-In" : (stackView.currentItem ? stackView.currentItem.objectName : "")
                font: toolBar.home ? Theme.headline : Theme.title
                color: Theme.text
                elide: Text.ElideRight
                Layout.leftMargin: toolBar.home ? 2 : 0
            }

            // Release tag, so testers can tell builds apart
            SiPill {
                visible: toolBar.home
                text: SystemProperties.releaseString + " \u00b7 " + SystemProperties.versionString
                Layout.leftMargin: 2
            }

            Item { Layout.fillWidth: true }

            SiIconButton {
                id: devicesButton
                visible: toolBar.home && UsbDevices.supported
                iconName: "usb"
                tip: qsTr("USB devices")
                onClicked: navigateTo("qrc:/gui/DevicesView.qml", DevicesView)

                Keys.onDownPressed: stackView.currentItem.forceActiveFocus(Qt.TabFocus)
            }

            SiIconButton {
                id: settingsButton
                visible: toolBar.home
                iconName: "gear"
                tip: qsTr("Settings") + (settingsShortcut.nativeText ? (" (" + settingsShortcut.nativeText + ")") : "")
                onClicked: navigateTo("qrc:/gui/SettingsView.qml", SettingsView)

                Keys.onDownPressed: stackView.currentItem.forceActiveFocus(Qt.TabFocus)

                Shortcut {
                    id: settingsShortcut
                    sequence: StandardKey.Preferences
                    onActivated: settingsButton.clicked()
                }
            }
        }
    }

    ErrorMessageDialog {
        id: noHwDecoderDialog
        text: qsTr("No working hardware video decoder was found. " +
                   "Your streaming performance may be severely degraded in this configuration.")
    }

    ErrorMessageDialog {
        id: xWaylandDialog
        text: qsTr("Hardware acceleration doesn't work on XWayland. Continuing on XWayland may result in poor streaming performance. " +
                   "Try running with QT_QPA_PLATFORM=wayland or switch to X11.")
    }

    NavigableMessageDialog {
        id: wow64Dialog
        standardButtons: Dialog.Ok | Dialog.Cancel
        text: qsTr("This version of Stand-In isn't optimized for your PC. Please download the '%1' version of Stand-In for the best streaming performance.").arg(SystemProperties.friendlyNativeArchName)
        onAccepted: {
            Qt.openUrlExternally("https://github.com/r0mn-creator/stand-in-client/releases");
        }
    }

    ErrorMessageDialog {
        id: unmappedGamepadDialog
        property string unmappedGamepads : ""
        text: qsTr("These gamepads have no mapping and won't work while streaming:") + "\n" + unmappedGamepads
    }

    // This dialog appears when quitting via keyboard or gamepad button
    NavigableMessageDialog {
        id: quitConfirmationDialog
        title: qsTr("Quit Stand-In?")
        standardButtons: Dialog.Cancel | Dialog.Yes
        text: qsTr("Devices you're sending to a PC will be given back to this machine.")
        // For keyboard/gamepad navigation
        onAccepted: Qt.quit()
    }

    // HACK: This belongs in StreamSegue but keeping a dialog around after the parent
    // dies can trigger bugs in Qt 5.12 that cause the app to crash. For now, we will
    // host this dialog in a QML component that is never destroyed.
    //
    // To repro: Start a stream, cut the network connection to trigger the "Connection
    // terminated" dialog, wait until the app grid times out back to the PC grid, then
    // try to dismiss the dialog.
    ErrorMessageDialog {
        id: streamSegueErrorDialog

        property bool quitAfter: false

        onClosed: {
            if (quitAfter) {
                Qt.quit()
            }

            // StreamSegue assumes its dialog will be re-created each time we
            // start streaming, so fake it by wiping out the text each time.
            text = ""
            title = ""
        }
    }

    // Add a PC by name or address
    SiDialog {
        id: addPcDialog

        property bool adding: false
        property string error: ""

        title: qsTr("Add a PC")
        text: qsTr("Enter the PC's name or IP address. It needs Stand-In Server running.")

        onOpened: {
            error = ""
            addressField.forceActiveFocus()
        }
        onClosed: {
            addressField.clear()
            adding = false
        }

        function add() {
            var address = addressField.text.trim()
            if (!address || adding) {
                return
            }
            error = ""
            adding = true
            ComputerManager.addNewHostManually(address)
        }

        Connections {
            target: ComputerManager
            function onComputerAddCompleted(success, detectedPortBlocking) {
                if (!addPcDialog.adding) {
                    return
                }
                addPcDialog.adding = false
                if (success) {
                    addPcDialog.close()
                }
                else if (detectedPortBlocking) {
                    addPcDialog.error = qsTr("This network is blocking Stand-In. Try another network, or connect over Tailscale.")
                }
                else {
                    addPcDialog.error = qsTr("Couldn't reach %1. Check that it's on and Stand-In Server is running.").arg(addressField.text.trim())
                }
            }
        }

        SiInput {
            id: addressField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. big-pc or 192.168.1.20")
            enabled: !addPcDialog.adding
            error: addPcDialog.error !== ""

            Keys.onReturnPressed: addPcDialog.add()
            Keys.onEnterPressed: addPcDialog.add()
            Keys.onDownPressed: addButton.forceActiveFocus(Qt.TabFocus)
        }

        Label {
            Layout.fillWidth: true
            visible: addPcDialog.error !== ""
            text: addPcDialog.error
            font: Theme.caption
            color: Theme.danger
            wrapMode: Text.Wrap
        }

        buttons: [
            SiButton {
                kind: "secondary"
                text: qsTr("Cancel")
                onClicked: addPcDialog.close()
                Keys.onRightPressed: addButton.forceActiveFocus(Qt.TabFocus)
                Keys.onUpPressed: addressField.forceActiveFocus()
            },
            SiButton {
                id: addButton
                text: qsTr("Add")
                busy: addPcDialog.adding
                enabled: addressField.text.trim() !== ""
                onClicked: addPcDialog.add()
                Keys.onUpPressed: addressField.forceActiveFocus()
            }
        ]
    }
}
