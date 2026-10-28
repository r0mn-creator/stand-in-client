import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

import ComputerModel 1.0
import AppModel 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import StandIn 1.0
import "si"

// Stand-In home: one big card for the PC you most likely want, the rest in a row below
FocusScope {
    id: home
    objectName: qsTr("Your PCs")

    property ComputerModel computerModel: createModel()

    // Bumped whenever the model changes, so bindings that read get() refresh
    property int revision: 0
    property string selectedUuid: ""
    property string wakingUuid: ""

    readonly property int heroIndex: { revision; return pickHero() }
    readonly property var hero: { revision; return computerModel.get(heroIndex) }

    Settings {
        id: remembered
        category: "home"
        property string lastUsedPc: ""
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        revision++
        heroButton.forceActiveFocus(Qt.TabFocus)
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', home, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    Connections {
        target: computerModel
        function onDataChanged() { home.revision++; home.continueWaking() }
        function onRowsInserted() { home.revision++ }
        function onRowsRemoved() { home.revision++ }
        function onModelReset() { home.revision++ }
    }

    function indexOfUuid(uuid)
    {
        for (var i = 0; uuid && i < computerModel.rowCount(); i++) {
            if (computerModel.get(i).uuid === uuid) {
                return i
            }
        }
        return -1
    }

    // The PC the user picked, else the one they used last, else the first awake one
    function pickHero()
    {
        var count = computerModel.rowCount()
        if (count === 0) {
            return -1
        }

        var picked = indexOfUuid(selectedUuid)
        if (picked >= 0) {
            return picked
        }
        var last = indexOfUuid(remembered.lastUsedPc)
        if (last >= 0) {
            return last
        }
        for (var i = 0; i < count; i++) {
            var pc = computerModel.get(i)
            if (pc.online && pc.paired) {
                return i
            }
        }
        for (i = 0; i < count; i++) {
            if (computerModel.get(i).paired) {
                return i
            }
        }
        return 0
    }

    // What the hero card says and offers for a PC
    function stateOf(pc)
    {
        if (!pc || pc.name === undefined) {
            return { status: "", dot: Theme.subtle, action: "", checking: false }
        }
        if (pc.uuid === wakingUuid) {
            return { status: qsTr("Waking up…"), long: qsTr("Waking up…"), dot: Theme.muted, action: "", checking: true }
        }
        if (pc.statusUnknown) {
            return { status: qsTr("Checking…"), long: qsTr("Checking…"), dot: Theme.muted, action: "", checking: true }
        }
        if (!pc.online) {
            return pc.wakeable
                ? { status: qsTr("Asleep"), long: qsTr("Asleep"), dot: Theme.statusAsleep, action: "wake", checking: false }
                : { status: qsTr("Offline"), long: qsTr("Offline"), dot: Theme.statusOffline, action: "", checking: false }
        }
        if (!pc.paired) {
            return { status: qsTr("Not paired"), long: qsTr("Not paired · Pair once to use it"), dot: Theme.statusNotPaired, action: "pair", checking: false }
        }
        return { status: qsTr("Awake"), long: pc.busy ? qsTr("Awake · Your session is still running") : qsTr("Awake · Ready to connect"),
                 dot: Theme.statusAwake, action: "connect", checking: false }
    }

    function actionText(action)
    {
        switch (action) {
        case "connect": return qsTr("Connect")
        case "wake": return qsTr("Wake and connect")
        case "pair": return qsTr("Pair")
        }
        return ""
    }

    function heroAction()
    {
        var state = stateOf(hero)
        if (state.action === "connect") {
            connectTo(heroIndex)
        }
        else if (state.action === "wake") {
            wakingUuid = hero.uuid
            wakeTimeout.restart()
            computerModel.wakeComputer(heroIndex)
        }
        else if (state.action === "pair") {
            pairWith(heroIndex)
        }
    }

    // A PC we woke has come online: carry on and connect
    function continueWaking()
    {
        if (!wakingUuid) {
            return
        }
        var index = indexOfUuid(wakingUuid)
        var pc = computerModel.get(index)
        if (index >= 0 && pc.online) {
            wakingUuid = ""
            wakeTimeout.stop()
            if (pc.paired) {
                connectTo(index)
            }
        }
    }

    Timer {
        id: wakeTimeout
        interval: 90000
        onTriggered: {
            var index = indexOfUuid(home.wakingUuid)
            home.wakingUuid = ""
            messageDialog.show(qsTr("%1 didn't wake up").arg(index >= 0 ? computerModel.get(index).name : qsTr("The PC")),
                               qsTr("Check that it's plugged in and that Wake-on-LAN is turned on in its settings."))
        }
    }

    // Connect goes straight to the desktop; a running session is resumed instead
    function connectTo(index)
    {
        var pc = computerModel.get(index)
        if (!pc.serverSupported) {
            messageDialog.show(qsTr("Update Stand-In Server on %1").arg(pc.name),
                               qsTr("The server on this PC is too old for this version of Stand-In."))
            return
        }

        remembered.lastUsedPc = pc.uuid
        selectedUuid = pc.uuid

        var appModel = Qt.createQmlObject('import AppModel 1.0; AppModel {}', home, '')
        appModel.initialize(ComputerManager, index, false)

        var runningId = appModel.getRunningAppId()
        var appIndex = runningId !== 0 ? appModel.findAppById(runningId) : appModel.findApp("Desktop")
        if (appIndex < 0) {
            appIndex = appModel.getDirectLaunchAppIndex()
        }
        if (appIndex < 0) {
            // No desktop entry: let the user choose
            showAllApps(index)
            return
        }

        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": qsTr("Desktop"),
                                               "pcName": pc.name,
                                               "session": appModel.createSessionForApp(appIndex),
                                               "isResume": runningId !== 0
                                           })
        stackView.push(segue)
    }

    function showAllApps(index)
    {
        var component = Qt.createComponent("AppView.qml")
        var appView = component.createObject(stackView, {"computerIndex": index, "objectName": computerModel.get(index).name})
        stackView.push(appView)
    }

    function pairWith(index)
    {
        var pin = computerModel.generatePinString()
        computerModel.pairComputer(index, pin)
        pairDialog.pcName = computerModel.get(index).name
        pairDialog.pin = pin
        pairDialog.open()
    }

    function pairingComplete(error)
    {
        pairDialog.close()
        if (error !== undefined) {
            messageDialog.show(qsTr("Couldn't pair with %1").arg(pairDialog.pcName), error)
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight + Theme.spaceLg
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: column
            width: Math.min(Theme.sizeContentWidth, home.width - 2 * Theme.sizeGutter)
            anchors.horizontalCenter: parent.horizontalCenter
            // Sit a little above the middle of tall windows
            y: Math.max(0, (home.height - implicitHeight) * 0.4)
            spacing: 0

            SiSectionLabel {
                text: qsTr("Your PCs")
                topPadding: Theme.spaceXs
            }

            // The PC you most likely want
            SiCard {
                id: heroCard
                Layout.fillWidth: true
                implicitHeight: heroColumn.implicitHeight + 2 * Theme.spaceLg
                visible: { home.revision; return computerModel.rowCount() > 0 }

                readonly property var state: home.stateOf(home.hero)

                ColumnLayout {
                    id: heroColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 48
                        implicitHeight: 48

                        SiIcon {
                            anchors.fill: parent
                            visible: !heroCard.state.checking
                            glyph: "tower"
                            sourceSize: Qt.size(48, 48)
                        }

                        SiSpinner {
                            anchors.centerIn: parent
                            visible: heroCard.state.checking
                            size: 40
                        }
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spaceXs
                        Layout.maximumWidth: heroCard.width - 2 * Theme.spaceXl - 2 * Theme.sizeIconButton
                        text: home.hero.name || ""
                        font: Theme.display
                        color: Theme.text
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        text: heroCard.state.long || ""
                        font: Theme.body
                        color: Theme.muted
                    }

                    SiButton {
                        id: heroButton
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spaceMd
                        Layout.preferredWidth: Theme.sizeHeroButtonWidth
                        large: true
                        visible: heroCard.state.action !== ""
                        text: home.actionText(heroCard.state.action)
                        onClicked: home.heroAction()

                        KeyNavigation.down: pcRow.count > 0 ? pcRow : addTile
                        KeyNavigation.right: moreButton
                    }

                    // Keeps the card the same height when there's no button
                    Item {
                        visible: !heroButton.visible
                        Layout.topMargin: Theme.spaceMd
                        implicitHeight: Theme.sizeButtonLarge
                    }
                }

                SiIconButton {
                    id: moreButton
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Theme.spaceSm
                    iconName: "more"
                    tip: qsTr("More")
                    flat: true
                    onClicked: pcMenu.popup(moreButton, moreButton.width - pcMenu.width, moreButton.height + 4)

                    KeyNavigation.left: heroButton
                    KeyNavigation.down: heroButton
                }
            }

            // No PCs yet
            SiCard {
                Layout.fillWidth: true
                implicitHeight: emptyColumn.implicitHeight + 2 * Theme.spaceXl
                visible: !heroCard.visible

                ColumnLayout {
                    id: emptyColumn
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.spaceXl
                    spacing: Theme.spaceXs

                    SiSpinner {
                        Layout.alignment: Qt.AlignHCenter
                        size: 40
                        visible: StreamingPreferences.enableMdns
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spaceXs
                        text: StreamingPreferences.enableMdns ? qsTr("Looking for your PCs…") : qsTr("Add your PC")
                        font: Theme.title
                        color: Theme.text
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: StreamingPreferences.enableMdns
                              ? qsTr("Stand-In finds PCs on your network and on Tailscale.")
                              : qsTr("Automatic discovery is off, so add your PC by its name or address.")
                        font: Theme.body
                        color: Theme.muted
                        wrapMode: Text.Wrap
                    }

                    SiButton {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spaceXs
                        kind: StreamingPreferences.enableMdns ? "text" : "primary"
                        text: qsTr("Add PC manually")
                        onClicked: addPcDialog.open()
                    }
                }
            }

            // Every PC, plus Add PC
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spaceSm
                spacing: Theme.spaceSm

                ListView {
                    id: pcRow
                    Layout.preferredWidth: Math.min(contentWidth, column.width - addTile.width - Theme.spaceSm)
                    Layout.preferredHeight: Theme.sizeTileHeight
                    orientation: ListView.Horizontal
                    spacing: Theme.spaceSm
                    clip: true
                    model: computerModel
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: true
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: Theme.motionNormal

                    KeyNavigation.up: heroButton.visible ? heroButton : moreButton
                    KeyNavigation.right: addTile
                    Keys.onRightPressed: (event) => {
                        if (currentIndex < count - 1) {
                            incrementCurrentIndex()
                        }
                        else {
                            addTile.forceActiveFocus(Qt.TabFocus)
                        }
                    }
                    Keys.onReturnPressed: currentItem.clicked()
                    Keys.onEnterPressed: currentItem.clicked()

                    delegate: SiTile {
                        readonly property var state: { home.revision; return home.stateOf(computerModel.get(index)) }

                        name: model.name
                        status: state.status
                        statusColor: state.dot
                        checking: state.checking
                        selected: index === home.heroIndex
                        focusPolicy: Qt.NoFocus

                        // Focus is on the list; draw the ring on the current tile
                        SiFocusRing {
                            target: pcRow
                            visible: pcRow.activeFocus && pcRow.currentIndex === index && InputMode.keyboard
                            ringRadius: Theme.radiusMd
                        }

                        onClicked: {
                            pcRow.currentIndex = index
                            home.selectedUuid = model.uuid
                        }

                        onPressAndHold: {
                            home.selectedUuid = model.uuid
                            pcMenu.popup()
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: parent.pressAndHold()
                        }
                    }
                }

                SiAddTile {
                    id: addTile
                    text: qsTr("Add PC")
                    onClicked: addPcDialog.open()

                    KeyNavigation.left: pcRow
                    KeyNavigation.up: heroButton.visible ? heroButton : moreButton
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // What you can do with the PC in the big card
    SiMenu {
        id: pcMenu

        SiMenuItem {
            text: qsTr("All apps")
            iconName: "apps"
            visible: home.hero.online === true && home.hero.paired === true
            onTriggered: home.showAllApps(home.heroIndex)
        }
        SiMenuItem {
            text: qsTr("Wake")
            iconName: "power"
            visible: home.hero.online === false && home.hero.wakeable === true
            onTriggered: computerModel.wakeComputer(home.heroIndex)
        }
        SiMenuItem {
            text: qsTr("Rename")
            iconName: "stylus"
            onTriggered: {
                renameDialog.pcIndex = home.heroIndex
                renameDialog.open()
            }
        }
        SiMenuItem {
            text: qsTr("Test network")
            iconName: "globe"
            onTriggered: {
                computerModel.testConnectionForComputer(home.heroIndex)
                testConnectionDialog.open()
            }
        }
        SiMenuItem {
            text: qsTr("Remove")
            iconName: "close"
            danger: true
            onTriggered: {
                removeDialog.pcIndex = home.heroIndex
                removeDialog.open()
            }
        }
    }

    SiDialog {
        id: pairDialog

        property string pcName
        property string pin: "0000"

        title: qsTr("Pair with %1").arg(pcName)
        text: qsTr("On %1, open Stand-In from the tray and enter this code. You only do this once.").arg(pcName)

        // FIXME: closing doesn't interrupt the pairing attempt yet
        onOpened: pairCancel.forceActiveFocus(Qt.TabFocus)

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spaceXs

            Repeater {
                model: pairDialog.pin.split("")

                Rectangle {
                    width: 56
                    height: 64
                    radius: Theme.radiusSm
                    color: Theme.raised
                    border.width: 1
                    border.color: Theme.border

                    Label {
                        anchors.centerIn: parent
                        text: modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        color: Theme.text
                    }
                }
            }
        }

        SiStatus {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.spaceXs
            checking: true
            text: qsTr("Waiting for %1…").arg(pairDialog.pcName)
        }

        buttons: SiButton {
            id: pairCancel
            kind: "secondary"
            text: qsTr("Cancel")
            onClicked: pairDialog.close()
        }
    }

    SiDialog {
        id: renameDialog

        property int pcIndex: -1

        title: qsTr("Rename PC")
        onOpened: {
            nameField.text = computerModel.get(pcIndex).name
            nameField.selectAll()
            nameField.forceActiveFocus()
        }

        function save() {
            if (nameField.text.trim()) {
                computerModel.renameComputer(pcIndex, nameField.text.trim())
            }
            close()
        }

        SiInput {
            id: nameField
            Layout.fillWidth: true
            Keys.onReturnPressed: renameDialog.save()
            Keys.onEnterPressed: renameDialog.save()
        }

        buttons: [
            SiButton { kind: "secondary"; text: qsTr("Cancel"); onClicked: renameDialog.close() },
            SiButton { text: qsTr("Save"); onClicked: renameDialog.save() }
        ]
    }

    SiDialog {
        id: removeDialog

        property int pcIndex: -1
        readonly property string pcName: { home.revision; return computerModel.get(pcIndex).name || "" }

        title: qsTr("Remove %1?").arg(pcName)
        text: qsTr("You'll need to pair with it again to use it.")
        onOpened: removeCancel.forceActiveFocus(Qt.TabFocus)

        buttons: [
            SiButton {
                id: removeCancel
                kind: "secondary"
                text: qsTr("Cancel")
                onClicked: removeDialog.close()
                Keys.onRightPressed: removeConfirm.forceActiveFocus(Qt.TabFocus)
            },
            SiButton {
                id: removeConfirm
                kind: "danger"
                text: qsTr("Remove")
                onClicked: {
                    if (home.selectedUuid === computerModel.get(removeDialog.pcIndex).uuid) {
                        home.selectedUuid = ""
                    }
                    computerModel.deleteComputer(removeDialog.pcIndex)
                    removeDialog.close()
                }
                Keys.onLeftPressed: removeCancel.forceActiveFocus(Qt.TabFocus)
            }
        ]
    }

    SiDialog {
        id: messageDialog

        function show(title, text) {
            messageDialog.title = title
            messageDialog.text = text
            open()
        }

        onOpened: messageOk.forceActiveFocus(Qt.TabFocus)

        buttons: SiButton {
            id: messageOk
            text: qsTr("OK")
            onClicked: messageDialog.close()
        }
    }

    SiDialog {
        id: testConnectionDialog

        property bool testing: true

        title: qsTr("Network test")
        onAboutToShow: {
            testing = true
            text = qsTr("Checking whether this network lets Stand-In through. This takes a few seconds…")
        }
        onOpened: testOk.forceActiveFocus(Qt.TabFocus)

        function connectionTestComplete(result, blockedPorts)
        {
            testing = false
            if (result === -1) {
                text = qsTr("The test couldn't run because the test servers weren't reachable. Check your internet connection and try again.")
            }
            else if (result === 0) {
                text = qsTr("This network isn't blocking Stand-In. If you still can't connect, check the firewall on your PC.")
            }
            else {
                text = qsTr("This network is blocking Stand-In, so connecting over the internet may not work here. Blocked ports:") + "\n" + blockedPorts
            }
        }

        SiSpinner {
            Layout.alignment: Qt.AlignHCenter
            visible: testConnectionDialog.testing
        }

        buttons: SiButton {
            id: testOk
            text: qsTr("OK")
            onClicked: testConnectionDialog.close()
        }
    }
}
