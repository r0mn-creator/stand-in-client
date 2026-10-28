import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Window 2.2
import QtQuick.Layouts 1.3

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import SystemProperties 1.0
import StandIn 1.0
import "si"

Item {
    readonly property bool hideHeader: true

    property Session session
    property string appName
    property string stageText : isResume ? qsTr("Picking up where you left off") :
                                           qsTr("Setting up your screens")
    property bool isResume : false
    property bool quitAfter : false

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1…").arg(stage)
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.title = qsTr("Couldn't connect to %1").arg(appName)
        streamSegueErrorDialog.text = qsTr("Starting %1 failed (error %2).").arg(stage).arg(errorCode)

        if (failingPorts) {
            streamSegueErrorDialog.text += " " + qsTr("Check the firewall on the PC and your network for these ports: %1").arg(failingPorts)
        }
    }

    function connectionStarted()
    {
        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        connectingColumn.visible = false
        hintText.visible = false

        // Hide the window now that streaming has begun
        window.visible = false
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.title = qsTr("Couldn't connect to %1").arg(appName)
        streamSegueErrorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.replace(stackView.currentItem, component.createObject(stackView, {"appName": appName}), StackView.Immediate)

        // Show the Qt window again to show quit segue
        window.visible = true
    }

    function sessionFinished(portTestResult)
    {
        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("This network is blocking Stand-In, so connecting over the internet may not work here.")
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Pop the StreamSegue off the stack if this is a GUI-based app launch
        if (!quitAfter) {
            stackView.pop()
        }

        if (quitAfter && !streamSegueErrorDialog.text) {
            // If this was a CLI launch without errors, exit now
            Qt.quit()
        }
        else {
            // Show the Qt window again after streaming
            window.visible = true

            // Display any launch errors. We do this after
            // the Qt UI is visible again to prevent losing
            // focus on the dialog which would impact gamepad
            // users.
            if (streamSegueErrorDialog.text) {
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
        }
    }

    function sessionReadyForDeletion()
    {
        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        session = null
        gc()
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack
        toolBar.visible = true

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading
        toolBar.visible = false

        // Hook up our signals
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.readyForDeletion.connect(sessionReadyForDeletion)

        // Ensure the SystemProperties async thread is finished,
        // since it may currently be using the SDL video subsystem
        SystemProperties.waitForAsyncLoad()

        // Kick off the stream
        streamLoader.active = true
    }

    Timer {
        id: startSessionTimer
        onTriggered: {
            // Garbage collect QML stuff before we start streaming,
            // since we'll probably be streaming for a while and we
            // won't be able to GC during the stream.
            gc()

            // Run the streaming session to completion
            session.start()
        }
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            // Set the hint text. We do this here rather than
            // in the hintText control itself to synchronize
            // with Session.exec() which requires no concurrent
            // gamepad usage.
            hintText.text = qsTr("To disconnect, press %1").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ?
                                                  qsTr("Start + Select + L1 + R1") : qsTr("Ctrl + Alt + Shift + Q"))

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // This spinner is shown only after session.initialize() has completed
            // to prevent active animations from running during decoder probing,
            // which causes re-entrant event loop livelocks with libdecor-gtk.
            stageSpinner.visible = true

            // Don't wait unless we have toasts to display
            startSessionTimer.interval = 0

            // Display the toasts together in a vertical centered arrangement
            var yOffset = 0
            for (var i = 0; i < session.launchWarnings.length; i++) {
                var text = session.launchWarnings[i]
                console.warn(text)

                // Show the tooltip for 3 seconds
                var toast = Qt.createQmlObject('import QtQuick.Controls 2.2; ToolTip {}', parent, '')
                toast.timeout = 3000
                toast.text = text
                toast.y += yOffset
                toast.visible = true

                // Offset the next toast below the previous one
                yOffset = toast.y + toast.padding + toast.height

                // Allow an extra 500 ms for the tooltip's fade-out animation to finish
                startSessionTimer.interval = toast.timeout + 500;
            }

            // Start the timer to wait for toasts (or start the session immediately)
            startSessionTimer.start()
        }

        sourceComponent: Item {}
    }

    // Connecting: the PC's name, what's happening, and a way out
    ColumnLayout {
        id: connectingColumn
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.sizeGutter, Theme.sizeContentWidth)
        spacing: 0

        SiSpinner {
            id: stageSpinner
            Layout.alignment: Qt.AlignHCenter
            size: 48
            visible: false
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceLg
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Connecting to %1…").arg(appName)
            font: Theme.title
            color: Theme.text
            wrapMode: Text.Wrap
        }

        Label {
            id: stageLabel
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceXxs
            horizontalAlignment: Text.AlignHCenter
            text: stageText
            font: Theme.label
            color: Theme.muted
            wrapMode: Text.Wrap
        }

        SiButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.spaceLg
            kind: "secondary"
            text: qsTr("Cancel")
            visible: stageSpinner.visible && session !== null
            onClicked: session.interrupt()
        }
    }

    Label {
        id: hintText
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spaceXxl
        anchors.horizontalCenter: parent.horizontalCenter
        font: Theme.caption
        color: Theme.subtle
    }
}
