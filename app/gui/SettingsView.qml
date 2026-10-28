import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import StreamingPreferences 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import StandIn 1.0
import "si"

// Stand-In settings: categories on the left, their options in groups on the right.
// Narrow windows show the category list first and one category at a time.
FocusScope {
    id: settingsPage
    objectName: qsTr("Settings")

    signal languageChanged()

    property int category: 0
    readonly property bool narrow: width < 760
    property bool showingCategory: false

    readonly property var categories: [
        { title: qsTr("Display & quality"), icon: "display", page: displayPage },
        { title: qsTr("Audio"), icon: "speaker", page: audioPage },
        { title: qsTr("Input"), icon: "keyboard", page: inputPage },
        { title: qsTr("Controllers"), icon: "gamepad", page: controllersPage },
        { title: qsTr("Devices"), icon: "usb", page: devicesPage },
        { title: qsTr("Appearance"), icon: "palette", page: appearancePage },
        { title: qsTr("Advanced"), icon: "sliders", page: advancedPage },
        { title: qsTr("About"), icon: "info", page: aboutPage }
    ]

    function openCategory(index) {
        category = index
        showingCategory = true
        content.contentY = 0
    }

    StackView.onActivated: {
        // Up and down move through every control on the page, like Tab
        SdlGamepadKeyNavigation.setUiNavMode(true)
        sidebarRepeater.itemAt(category).forceActiveFocus(Qt.TabFocus)
    }

    StackView.onDeactivating: {
        SdlGamepadKeyNavigation.setUiNavMode(false)

        // Save the prefs so the Session can observe the changes
        StreamingPreferences.save()
    }

    Component.onDestruction: {
        // Also save on destruction, since closing the window skips deactivating
        StreamingPreferences.save()
    }

    // Quality follows the resolution and frame rate unless the user set it by hand
    function updateBitrateForSelection() {
        if (StreamingPreferences.autoAdjustBitrate) {
            StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(StreamingPreferences.width,
                                                                                      StreamingPreferences.height,
                                                                                      StreamingPreferences.fps,
                                                                                      StreamingPreferences.enableYUV444)
        }
    }

    // Keep the focused control on screen while navigating with keys or a gamepad
    Connections {
        target: window
        function onActiveFocusItemChanged() {
            var item = window.activeFocusItem
            if (!item || !content.contentItem || !isInside(item, content.contentItem)) {
                return
            }
            var pos = item.mapToItem(content.contentItem, 0, 0)
            var margin = 40
            if (pos.y < content.contentY + margin) {
                content.contentY = Math.max(0, pos.y - margin)
            }
            else if (pos.y + item.height > content.contentY + content.height - margin) {
                content.contentY = Math.min(content.contentHeight - content.height, pos.y + item.height - content.height + margin)
            }
        }
    }

    function isInside(item, ancestor) {
        for (; item; item = item.parent) {
            if (item === ancestor) {
                return true
            }
        }
        return false
    }

    RowLayout {
        // Sidebar and options sit together in the middle of wide windows
        width: Math.min(parent.width - 2 * Theme.sizeGutter, Theme.sizeSidebarWidth + Theme.spaceXl + 560 + 12)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spaceXl

        // Categories
        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Theme.spaceXs
            Layout.preferredWidth: settingsPage.narrow ? -1 : Theme.sizeSidebarWidth
            Layout.fillWidth: settingsPage.narrow
            visible: !settingsPage.narrow || !settingsPage.showingCategory
            spacing: 2

            Repeater {
                id: sidebarRepeater
                model: settingsPage.categories

                AbstractButton {
                    id: categoryButton

                    readonly property bool selected: !settingsPage.narrow && index === settingsPage.category

                    Layout.fillWidth: true
                    implicitHeight: 44
                    focusPolicy: Qt.StrongFocus
                    onClicked: settingsPage.openCategory(index)
                    onActiveFocusChanged: if (activeFocus && !settingsPage.narrow) settingsPage.category = index
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()

                    contentItem: RowLayout {
                        spacing: Theme.spaceSm

                        SiIcon {
                            Layout.leftMargin: Theme.spaceSm
                            glyph: modelData.icon
                            color: categoryButton.selected ? Theme.accent : Theme.muted
                            sourceSize: Qt.size(Theme.sizeIconSmall, Theme.sizeIconSmall)
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.title
                            font: categoryButton.selected ? Theme.bodyStrong : Theme.body
                            color: categoryButton.selected ? Theme.text : Theme.muted
                        }

                        SiIcon {
                            visible: settingsPage.narrow
                            Layout.rightMargin: Theme.spaceSm
                            glyph: "chevron-right"
                            color: Theme.subtle
                            sourceSize: Qt.size(Theme.sizeIconSmall, Theme.sizeIconSmall)
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: categoryButton.selected || categoryButton.hovered ? Theme.raised : "transparent"

                        SiFocusRing { target: categoryButton; ringRadius: Theme.radiusSm }
                    }
                }
            }
        }

        // The category's options
        Flickable {
            id: content
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !settingsPage.narrow || settingsPage.showingCategory
            contentHeight: pageColumn.implicitHeight + Theme.spaceXl
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: pageColumn
                width: Math.min(560, content.width - 12)
                spacing: 0

                SiButton {
                    visible: settingsPage.narrow
                    kind: "text"
                    text: qsTr("‹  All settings")
                    onClicked: settingsPage.showingCategory = false
                }

                Label {
                    Layout.topMargin: Theme.spaceXs
                    text: settingsPage.categories[settingsPage.category].title
                    font: Theme.title
                    color: Theme.text
                }

                Loader {
                    Layout.fillWidth: true
                    sourceComponent: settingsPage.categories[settingsPage.category].page
                }
            }
        }
    }

    // ---- Display & quality ---------------------------------------------------

    Component {
        id: displayPage

        ColumnLayout {
            id: displayRoot
            spacing: 0

            function resolutionOptions() {
                var options = []
                function add(text, w, h) {
                    var max = SystemProperties.maximumResolution
                    if (max.width > 0 && w * h > max.width * max.height) {
                        return
                    }
                    for (var i = 0; i < options.length; i++) {
                        if (options[i].value === w + "x" + h) {
                            return
                        }
                    }
                    options.push({ text: text, value: w + "x" + h })
                }

                SystemProperties.refreshDisplays()
                for (var d = 0; ; d++) {
                    var screen = SystemProperties.getNativeResolution(d)
                    if (screen.width === 0) {
                        break
                    }
                    add(d === 0 ? qsTr("Match this screen (%1 × %2)").arg(screen.width).arg(screen.height)
                                : qsTr("Match screen %1 (%2 × %3)").arg(d + 1).arg(screen.width).arg(screen.height),
                        screen.width, screen.height)
                }
                add("720p", 1280, 720)
                add("1080p", 1920, 1080)
                add("1440p", 2560, 1440)
                add("4K", 3840, 2160)

                var current = StreamingPreferences.width + "x" + StreamingPreferences.height
                if (!options.some(function(o) { return o.value === current })) {
                    options.push({ text: qsTr("Custom (%1 × %2)").arg(StreamingPreferences.width).arg(StreamingPreferences.height), value: current })
                }
                options.push({ text: qsTr("Custom…"), value: "custom" })
                return options
            }

            function frameRateOptions() {
                var rates = [30, 60, 90, 120]
                for (var d = 0; ; d++) {
                    var rate = SystemProperties.getRefreshRate(d)
                    if (rate === 0) {
                        break
                    }
                    if (rates.indexOf(rate) < 0) {
                        rates.push(rate)
                    }
                }
                if (rates.indexOf(StreamingPreferences.fps) < 0) {
                    rates.push(StreamingPreferences.fps)
                }
                rates.sort(function(a, b) { return a - b })
                var options = rates.map(function(r) { return { text: qsTr("%1 fps").arg(r), value: r } })
                options.push({ text: qsTr("Custom…"), value: -1 })
                return options
            }

            SiSectionLabel { text: qsTr("Picture") }

            SiGroup {
                Layout.fillWidth: true

                SiPicker {
                    id: resolutionPicker
                    title: qsTr("Resolution")
                    subtitle: qsTr("Match this screen gives the sharpest picture.")
                    options: displayRoot.resolutionOptions()
                    currentValue: StreamingPreferences.width + "x" + StreamingPreferences.height
                    onActivated: (value) => {
                        if (value === "custom") {
                            customResolutionDialog.open()
                            return
                        }
                        var size = value.split("x")
                        StreamingPreferences.width = parseInt(size[0])
                        StreamingPreferences.height = parseInt(size[1])
                        settingsPage.updateBitrateForSelection()
                        options = displayRoot.resolutionOptions()
                    }
                }

                SiPicker {
                    id: frameRatePicker
                    title: qsTr("Frame rate")
                    subtitle: qsTr("Higher is smoother and uses more bandwidth.")
                    options: displayRoot.frameRateOptions()
                    currentValue: StreamingPreferences.fps
                    onActivated: (value) => {
                        if (value === -1) {
                            customFpsDialog.open()
                            return
                        }
                        StreamingPreferences.fps = value
                        settingsPage.updateBitrateForSelection()
                    }
                }

                SiPicker {
                    title: qsTr("Quality")
                    subtitle: StreamingPreferences.autoAdjustBitrate
                              ? qsTr("Starts at %1 Mbps and adapts to your network.").arg(StreamingPreferences.bitrateKbps / 1000)
                              : qsTr("Fixed. Lower it if the picture stutters.")
                    options: [
                        { text: qsTr("Automatic"), value: true },
                        { text: qsTr("Manual"), value: false }
                    ]
                    currentValue: StreamingPreferences.autoAdjustBitrate
                    onActivated: (value) => {
                        StreamingPreferences.autoAdjustBitrate = value
                        settingsPage.updateBitrateForSelection()
                    }
                }

                SiSliderRow {
                    visible: !StreamingPreferences.autoAdjustBitrate
                    title: qsTr("Bitrate")
                    valueText: qsTr("%1 Mbps").arg(value / 1000)
                    from: 500
                    to: StreamingPreferences.unlockBitrate ? 500000 : 150000
                    stepSize: 500
                    value: StreamingPreferences.bitrateKbps
                    onMoved: StreamingPreferences.bitrateKbps = value
                }
            }

            SiSectionLabel { text: qsTr("Window") }

            SiGroup {
                Layout.fillWidth: true

                SiPicker {
                    visible: SystemProperties.hasDesktopEnvironment
                    enabled: !SystemProperties.rendererAlwaysFullScreen
                    title: qsTr("Show your PC")
                    options: [
                        { text: qsTr("Full screen"), value: StreamingPreferences.WM_FULLSCREEN },
                        { text: qsTr("Borderless window"), value: StreamingPreferences.WM_FULLSCREEN_DESKTOP },
                        { text: qsTr("In a window"), value: StreamingPreferences.WM_WINDOWED }
                    ]
                    currentValue: StreamingPreferences.windowMode
                    onActivated: (value) => StreamingPreferences.windowMode = value
                }

                SiSwitchRow {
                    title: qsTr("Show performance stats")
                    subtitle: qsTr("Frame rate, delay and quality in a corner of the screen.")
                    isOn: StreamingPreferences.showPerformanceOverlay
                    onFlipped: (checked) => StreamingPreferences.showPerformanceOverlay = checked
                }

                SiSwitchRow {
                    title: qsTr("Keep this screen awake")
                    isOn: StreamingPreferences.keepAwake
                    onFlipped: (checked) => StreamingPreferences.keepAwake = checked
                }
            }

            SiDialog {
                id: customResolutionDialog

                title: qsTr("Custom resolution")
                text: qsTr("Width and height in pixels.")
                onOpened: widthField.forceActiveFocus()

                function valid() {
                    return widthField.acceptableInput && heightField.acceptableInput
                }
                function save() {
                    if (!valid()) {
                        return
                    }
                    StreamingPreferences.width = parseInt(widthField.text)
                    StreamingPreferences.height = parseInt(heightField.text)
                    settingsPage.updateBitrateForSelection()
                    resolutionPicker.options = displayRoot.resolutionOptions()
                    close()
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceXs

                    SiInput {
                        id: widthField
                        Layout.fillWidth: true
                        placeholderText: StreamingPreferences.width
                        validator: IntValidator { bottom: 256; top: 8192 }
                        inputMethodHints: Qt.ImhDigitsOnly
                        Keys.onReturnPressed: heightField.forceActiveFocus()
                    }
                    Label { text: "×"; font: Theme.title; color: Theme.muted }
                    SiInput {
                        id: heightField
                        Layout.fillWidth: true
                        placeholderText: StreamingPreferences.height
                        validator: IntValidator { bottom: 256; top: 8192 }
                        inputMethodHints: Qt.ImhDigitsOnly
                        Keys.onReturnPressed: customResolutionDialog.save()
                    }
                }

                buttons: [
                    SiButton { kind: "secondary"; text: qsTr("Cancel"); onClicked: customResolutionDialog.close() },
                    SiButton { text: qsTr("Use"); enabled: customResolutionDialog.valid(); onClicked: customResolutionDialog.save() }
                ]
            }

            SiDialog {
                id: customFpsDialog

                title: qsTr("Custom frame rate")
                text: qsTr("Frames per second, from 10 to 500.")
                onOpened: fpsField.forceActiveFocus()

                function save() {
                    if (!fpsField.acceptableInput) {
                        return
                    }
                    StreamingPreferences.fps = parseInt(fpsField.text)
                    settingsPage.updateBitrateForSelection()
                    frameRatePicker.options = displayRoot.frameRateOptions()
                    close()
                }

                SiInput {
                    id: fpsField
                    Layout.fillWidth: true
                    placeholderText: StreamingPreferences.fps
                    validator: IntValidator { bottom: 10; top: 500 }
                    inputMethodHints: Qt.ImhDigitsOnly
                    Keys.onReturnPressed: customFpsDialog.save()
                }

                buttons: [
                    SiButton { kind: "secondary"; text: qsTr("Cancel"); onClicked: customFpsDialog.close() },
                    SiButton { text: qsTr("Use"); enabled: fpsField.acceptableInput; onClicked: customFpsDialog.save() }
                ]
            }
        }
    }

    // ---- Audio ---------------------------------------------------------------

    Component {
        id: audioPage

        ColumnLayout {
            spacing: 0

            SiSectionLabel { text: qsTr("Sound") }

            SiGroup {
                Layout.fillWidth: true

                SiPicker {
                    title: qsTr("Sound output")
                    options: [
                        { text: qsTr("Stereo"), value: StreamingPreferences.AC_STEREO },
                        { text: qsTr("5.1 surround"), value: StreamingPreferences.AC_51_SURROUND },
                        { text: qsTr("7.1 surround"), value: StreamingPreferences.AC_71_SURROUND }
                    ]
                    currentValue: StreamingPreferences.audioConfig
                    onActivated: (value) => StreamingPreferences.audioConfig = value
                }

                SiSwitchRow {
                    title: qsTr("Play sound on the PC too")
                    isOn: StreamingPreferences.playAudioOnHost
                    onFlipped: (checked) => StreamingPreferences.playAudioOnHost = checked
                }

                SiSwitchRow {
                    visible: SystemProperties.hasDesktopEnvironment
                    title: qsTr("Mute when Stand-In isn't the active window")
                    isOn: StreamingPreferences.muteOnFocusLoss
                    onFlipped: (checked) => StreamingPreferences.muteOnFocusLoss = checked
                }
            }
        }
    }

    // ---- Input ---------------------------------------------------------------

    Component {
        id: inputPage

        ColumnLayout {
            spacing: 0

            SiSectionLabel { text: qsTr("Mouse and touch") }

            SiGroup {
                Layout.fillWidth: true

                SiPicker {
                    title: qsTr("Mouse works like")
                    subtitle: StreamingPreferences.absoluteMouseMode
                              ? qsTr("The pointer goes exactly where you point. Best for desktop work.")
                              : qsTr("Raw movement. Best for games that capture the mouse.")
                    options: [
                        { text: qsTr("A desktop"), value: true },
                        { text: qsTr("A game"), value: false }
                    ]
                    currentValue: StreamingPreferences.absoluteMouseMode
                    onActivated: (value) => StreamingPreferences.absoluteMouseMode = value
                }

                SiPicker {
                    title: qsTr("Touch works like")
                    options: [
                        { text: qsTr("Direct touch"), value: true },
                        { text: qsTr("A trackpad"), value: false }
                    ]
                    currentValue: StreamingPreferences.absoluteTouchMode
                    onActivated: (value) => StreamingPreferences.absoluteTouchMode = value
                }

                SiSwitchRow {
                    title: qsTr("Swap left and right buttons")
                    isOn: StreamingPreferences.swapMouseButtons
                    onFlipped: (checked) => StreamingPreferences.swapMouseButtons = checked
                }

                SiSwitchRow {
                    title: qsTr("Reverse scrolling")
                    isOn: StreamingPreferences.reverseScrollDirection
                    onFlipped: (checked) => StreamingPreferences.reverseScrollDirection = checked
                }
            }

            SiSectionLabel {
                text: qsTr("Keyboard")
                visible: SystemProperties.hasDesktopEnvironment
            }

            SiGroup {
                Layout.fillWidth: true
                visible: SystemProperties.hasDesktopEnvironment

                SiPicker {
                    title: qsTr("Send system shortcuts to the PC")
                    subtitle: qsTr("Alt+Tab, the Windows key and similar.")
                    options: [
                        { text: qsTr("Never"), value: StreamingPreferences.CSK_OFF },
                        { text: qsTr("In full screen"), value: StreamingPreferences.CSK_FULLSCREEN },
                        { text: qsTr("Always"), value: StreamingPreferences.CSK_ALWAYS }
                    ]
                    currentValue: StreamingPreferences.captureSysKeysMode
                    onActivated: (value) => StreamingPreferences.captureSysKeysMode = value
                }
            }
        }
    }

    // ---- Controllers ---------------------------------------------------------

    Component {
        id: controllersPage

        ColumnLayout {
            spacing: 0

            SiSectionLabel { text: qsTr("Controllers") }

            SiGroup {
                Layout.fillWidth: true

                SiSwitchRow {
                    title: qsTr("Swap A/B and X/Y")
                    subtitle: qsTr("For a Nintendo-style button layout.")
                    isOn: StreamingPreferences.swapFaceButtons
                    onFlipped: (checked) => StreamingPreferences.swapFaceButtons = checked
                }

                SiSwitchRow {
                    title: qsTr("Use a controller as a mouse")
                    subtitle: qsTr("Hold Start to switch between controller and mouse.")
                    isOn: StreamingPreferences.gamepadMouse
                    onFlipped: (checked) => StreamingPreferences.gamepadMouse = checked
                }

                SiSwitchRow {
                    title: qsTr("Always connect controller 1")
                    subtitle: qsTr("The PC sees a controller even when none is plugged in here.")
                    isOn: !StreamingPreferences.multiController
                    onFlipped: (checked) => StreamingPreferences.multiController = !checked
                }

                SiSwitchRow {
                    visible: SystemProperties.hasDesktopEnvironment
                    title: qsTr("Use controllers in the background")
                    subtitle: qsTr("Controllers keep working when Stand-In isn't the active window.")
                    isOn: StreamingPreferences.backgroundGamepad
                    onFlipped: (checked) => StreamingPreferences.backgroundGamepad = checked
                }
            }
        }
    }

    // ---- Devices -------------------------------------------------------------

    Component {
        id: devicesPage

        ColumnLayout {
            spacing: 0

            SiSectionLabel { text: qsTr("USB") }

            SiGroup {
                Layout.fillWidth: true

                SiRow {
                    title: qsTr("USB devices")
                    subtitle: qsTr("Send wheels, sticks, tablets and other devices to your PC.")
                    iconName: "usb"
                    chevron: true
                    onClicked: navigateTo("qrc:/gui/DevicesView.qml", DevicesView)
                }
            }
        }
    }

    // ---- Appearance ----------------------------------------------------------

    Component {
        id: appearancePage

        ColumnLayout {
            spacing: 0

            SiSectionLabel { text: qsTr("Look") }

            SiGroup {
                Layout.fillWidth: true

                SiRow {
                    title: qsTr("Theme")
                    subtitle: qsTr("More themes are on the way.")

                    Row {
                        spacing: Theme.spaceXs

                        Repeater {
                            model: [Theme.ground, Theme.surface, Theme.accent]

                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: modelData
                                border.width: 1
                                border.color: Theme.borderStrong
                            }
                        }
                    }

                    Label {
                        text: "Midnight Slate"
                        font: Theme.body
                        color: Theme.muted
                    }
                }

                SiPicker {
                    visible: SystemProperties.hasDesktopEnvironment
                    title: qsTr("Open Stand-In")
                    options: [
                        { text: qsTr("In a window"), value: StreamingPreferences.UI_WINDOWED },
                        { text: qsTr("Maximized"), value: StreamingPreferences.UI_MAXIMIZED },
                        { text: qsTr("Full screen"), value: StreamingPreferences.UI_FULLSCREEN }
                    ]
                    currentValue: StreamingPreferences.uiDisplayMode
                    onActivated: (value) => StreamingPreferences.uiDisplayMode = value
                }

                SiPicker {
                    title: qsTr("Language")
                    options: [
            { text: qsTr("Automatic"), value: StreamingPreferences.LANG_AUTO },
            { text: "Deutsch", value: StreamingPreferences.LANG_DE },
            { text: "English", value: StreamingPreferences.LANG_EN },
            { text: "Français", value: StreamingPreferences.LANG_FR },
            { text: "简体中文", value: StreamingPreferences.LANG_ZH_CN },
            { text: "Norwegian Bokmål", value: StreamingPreferences.LANG_NB_NO },
            { text: "русский", value: StreamingPreferences.LANG_RU },
            { text: "Español", value: StreamingPreferences.LANG_ES },
            { text: "日本語", value: StreamingPreferences.LANG_JA },
            { text: "Tiếng Việt", value: StreamingPreferences.LANG_VI },
            { text: "ภาษาไทย", value: StreamingPreferences.LANG_TH },
            { text: "한국어", value: StreamingPreferences.LANG_KO },
            { text: "Magyar", value: StreamingPreferences.LANG_HU },
            { text: "Nederlands", value: StreamingPreferences.LANG_NL },
            { text: "Svenska", value: StreamingPreferences.LANG_SV },
            { text: "Türkçe", value: StreamingPreferences.LANG_TR },
            { text: "繁體中文", value: StreamingPreferences.LANG_ZH_TW },
            { text: "Português", value: StreamingPreferences.LANG_PT },
            { text: "Português do Brasil", value: StreamingPreferences.LANG_PT_BR },
            { text: "Ελληνικά", value: StreamingPreferences.LANG_EL },
            { text: "Italiano", value: StreamingPreferences.LANG_IT },
            { text: "Język polski", value: StreamingPreferences.LANG_PL },
            { text: "Čeština", value: StreamingPreferences.LANG_CS },
            { text: "Български", value: StreamingPreferences.LANG_BG },
            { text: "தமிழ்", value: StreamingPreferences.LANG_TA }
                    ]
                    currentValue: StreamingPreferences.language
                    onActivated: (value) => {
                        // Retranslating is expensive, so only do it if the language actually changed
                        if (StreamingPreferences.language === value) {
                            return
                        }
                        StreamingPreferences.language = value
                        if (!StreamingPreferences.retranslate()) {
                            ToolTip.show(qsTr("Restart Stand-In to finish changing the language"), 5000)
                        }
                        else {
                            // AppView stops working after retranslate(), so going back clears it
                            window.clearOnBack = true
                            settingsPage.languageChanged()
                        }
                    }
                }
            }
        }
    }

    // ---- Advanced ------------------------------------------------------------

    Component {
        id: advancedPage

        ColumnLayout {
            spacing: 0

            SiSectionLabel { text: qsTr("Video") }

            SiGroup {
                Layout.fillWidth: true

                SiPicker {
                    title: qsTr("Video format")
                    subtitle: qsTr("Automatic picks the best one both machines support.")
                    options: [
                        { text: qsTr("Automatic"), value: StreamingPreferences.VCC_AUTO },
                        { text: "AV1", value: StreamingPreferences.VCC_FORCE_AV1 },
                        { text: "HEVC (H.265)", value: StreamingPreferences.VCC_FORCE_HEVC },
                        { text: "H.264", value: StreamingPreferences.VCC_FORCE_H264 }
                    ]
                    currentValue: StreamingPreferences.videoCodecConfig
                    onActivated: (value) => StreamingPreferences.videoCodecConfig = value
                }

                SiPicker {
                    title: qsTr("Video decoding")
                    options: [
                        { text: qsTr("Automatic"), value: StreamingPreferences.VDS_AUTO },
                        { text: qsTr("Hardware only"), value: StreamingPreferences.VDS_FORCE_HARDWARE },
                        { text: qsTr("Software only"), value: StreamingPreferences.VDS_FORCE_SOFTWARE }
                    ]
                    currentValue: StreamingPreferences.videoDecoderSelection
                    onActivated: (value) => StreamingPreferences.videoDecoderSelection = value
                }

                SiSwitchRow {
                    title: qsTr("HDR")
                    subtitle: SystemProperties.supportsHdr ? qsTr("Brighter highlights when the PC and this screen both support it.")
                                                           : qsTr("This screen or decoder doesn't support HDR.")
                    enabled: SystemProperties.supportsHdr
                    isOn: StreamingPreferences.enableHdr
                    onFlipped: (checked) => StreamingPreferences.enableHdr = checked
                }

                SiSwitchRow {
                    title: qsTr("Full color detail (YUV 4:4:4)")
                    subtitle: qsTr("Sharper text, more bandwidth. Needs support on both machines.")
                    isOn: StreamingPreferences.enableYUV444
                    onFlipped: (checked) => {
                        StreamingPreferences.enableYUV444 = checked
                        settingsPage.updateBitrateForSelection()
                    }
                }

                SiSwitchRow {
                    title: qsTr("V-Sync")
                    subtitle: qsTr("Off is a little faster but can tear.")
                    isOn: StreamingPreferences.enableVsync
                    onFlipped: (checked) => StreamingPreferences.enableVsync = checked
                }

                SiSwitchRow {
                    title: qsTr("Frame pacing")
                    subtitle: qsTr("Smoother motion for a little more delay.")
                    enabled: StreamingPreferences.enableVsync
                    isOn: StreamingPreferences.enableVsync && StreamingPreferences.framePacing
                    onFlipped: (checked) => StreamingPreferences.framePacing = checked
                }

                SiSwitchRow {
                    title: qsTr("Allow very high bitrates")
                    subtitle: qsTr("Raises the manual limit from 150 to 500 Mbps.")
                    isOn: StreamingPreferences.unlockBitrate
                    onFlipped: (checked) => StreamingPreferences.unlockBitrate = checked
                }
            }

            SiSectionLabel { text: qsTr("Network") }

            SiGroup {
                Layout.fillWidth: true

                SiSwitchRow {
                    title: qsTr("Find PCs automatically")
                    subtitle: qsTr("Looks on your local network.")
                    isOn: StreamingPreferences.enableMdns
                    onFlipped: (checked) => {
                        StreamingPreferences.enableMdns = checked
                        // Restart polling so the change takes effect
                        ComputerManager.stopPollingAsync()
                        ComputerManager.startPolling()
                    }
                }

                SiSwitchRow {
                    title: qsTr("Check for blocked networks")
                    isOn: StreamingPreferences.detectNetworkBlocking
                    onFlipped: (checked) => StreamingPreferences.detectNetworkBlocking = checked
                }

                SiSwitchRow {
                    title: qsTr("Warn about a weak connection")
                    isOn: StreamingPreferences.connectionWarnings
                    onFlipped: (checked) => StreamingPreferences.connectionWarnings = checked
                }
            }

            SiSectionLabel { text: qsTr("Sessions") }

            SiGroup {
                Layout.fillWidth: true

                SiSwitchRow {
                    title: qsTr("Close the app on the PC when you disconnect")
                    isOn: StreamingPreferences.quitAppAfter
                    onFlipped: (checked) => StreamingPreferences.quitAppAfter = checked
                }

                SiSwitchRow {
                    title: qsTr("Tune games for streaming")
                    subtitle: qsTr("Lets supported games adjust their settings while you're connected.")
                    isOn: StreamingPreferences.gameOptimizations
                    onFlipped: (checked) => StreamingPreferences.gameOptimizations = checked
                }

                SiSwitchRow {
                    title: qsTr("Show setup warnings")
                    isOn: StreamingPreferences.configurationWarnings
                    onFlipped: (checked) => StreamingPreferences.configurationWarnings = checked
                }

                SiSwitchRow {
                    visible: SystemProperties.hasDiscordIntegration
                    title: qsTr("Show activity in Discord")
                    isOn: StreamingPreferences.richPresence
                    onFlipped: (checked) => StreamingPreferences.richPresence = checked
                }
            }
        }
    }

    // ---- About ---------------------------------------------------------------

    Component {
        id: aboutPage

        ColumnLayout {
            spacing: 0

            SiSectionLabel { text: qsTr("Stand-In Client") }

            SiGroup {
                Layout.fillWidth: true

                SiRow {
                    title: qsTr("Version")
                    value: SystemProperties.releaseString + " · " + SystemProperties.versionString
                }

                SiRow {
                    title: qsTr("Source code")
                    subtitle: qsTr("Stand-In is free software under the GNU GPL v3.")
                }
            }

            SiSectionLabel { text: qsTr("Built on") }

            SiGroup {
                Layout.fillWidth: true

                SiRow {
                    title: "Moonlight"
                    subtitle: qsTr("The streaming client this app grew from. GPL v3.")
                }

                SiRow {
                    title: "Artemis"
                    subtitle: qsTr("The Android client Stand-In for Android grew from. GPL v3.")
                }

                SiRow {
                    title: "Apollo and Sunshine"
                    subtitle: qsTr("The streaming server Stand-In Server grew from. GPL v3.")
                }

                SiRow {
                    title: "Inter"
                    subtitle: qsTr("The typeface, by Rasmus Andersson. SIL Open Font License.")
                }
            }
        }
    }
}
