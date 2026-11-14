import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform 1.1

import "../"
import "../common"
import "../components"

Item {
    id: page

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        anchors.rightMargin: 24
        spacing: 24
        Layout.alignment: Qt.AlignTop

        Text {
            text: I18n.t("settings.title", "Settings")
            font.pixelSize: 28
            font.bold: true
            color: Theme.text
        }

        ScrollView {
            id: settingsScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            GridLayout {
                width: settingsScroll.availableWidth
                columns: width > 1050 ? 2 : 1
                columnSpacing: 24
                rowSpacing: 24

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 24

                    DaemonPanel { }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: appCol.implicitHeight + 32
                        color: Theme.card
                        radius: 8
                        border.color: Theme.border

                        ColumnLayout {
                            id: appCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text { text: I18n.t("settings.appearance", "Appearance"); font.pixelSize: 18; font.bold: true; color: Theme.text }
                            Text { text: I18n.t("settings.appearanceHelp", "Select your preferred color scheme for the application."); font.pixelSize: 14; color: Theme.subText; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                            GridLayout {
                                Layout.topMargin: 4
                                columns: 2
                                rowSpacing: 12
                                columnSpacing: 12

                                WinButton { text: I18n.t("settings.dark", "Dark Mode"); Layout.preferredWidth: 220; Layout.preferredHeight: 45; isAccent: Theme.currentTheme === "dark"; onClicked: { Theme.applyTheme("dark"); backend.saveSetting("theme", "dark") } }
                                WinButton { text: I18n.t("settings.light", "Light Mode"); Layout.preferredWidth: 220; Layout.preferredHeight: 45; isAccent: Theme.currentTheme === "light"; onClicked: { Theme.applyTheme("light"); backend.saveSetting("theme", "light") } }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: languageCol.implicitHeight + 32
                        color: Theme.card
                        radius: 8
                        border.color: Theme.border

                        ColumnLayout {
                            id: languageCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                LucideIcon { icon: Icons.language; size: Theme.iconSizeLarge; color: Theme.accent }
                                Text { text: I18n.t("settings.language", "Language"); font.pixelSize: 18; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                            }
                            Text { text: I18n.t("settings.languageHelp", "Choose the interface language. Translation text is stored in editable JSON files."); font.pixelSize: 14; color: Theme.subText; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 430 ? 2 : 1
                                rowSpacing: 10
                                columnSpacing: 10
                                WinButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    text: I18n.t("settings.english", "English")
                                    isAccent: I18n.language === "en"
                                    onClicked: { I18n.setLanguage("en"); if (typeof backend !== "undefined") backend.saveSetting("language", "en") }
                                }
                                WinButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    text: I18n.t("settings.indonesian", "Bahasa Indonesia")
                                    isAccent: I18n.language === "id"
                                    onClicked: { I18n.setLanguage("id"); if (typeof backend !== "undefined") backend.saveSetting("language", "id") }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                LucideIcon { icon: Icons.info; size: Theme.iconSize; color: Theme.info }
                                Text {
                                    Layout.fillWidth: true
                                    text: Theme.nerdFontAvailable
                                          ? I18n.format("settings.iconFontDetected", {"font": Theme.iconFontFamily}, "Nerd Font detected: " + Theme.iconFontFamily)
                                          : I18n.t("settings.iconFontFallback", "Nerd Font not detected. Using system-safe fallback symbols.")
                                    color: Theme.subText
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: dbCol.implicitHeight + 32
                        color: Theme.card
                        radius: 8
                        border.color: Theme.border

                        ColumnLayout {
                            id: dbCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text { text: I18n.t("settings.database", "Database Configuration"); font.pixelSize: 18; font.bold: true; color: Theme.text }
                            Text { text: I18n.t("settings.databaseHelp", "Manage where local telemetry and configuration data is stored."); font.pixelSize: 14; color: Theme.subText; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Layout.topMargin: 4

                                WinTextField {
                                    id: dbPathField
                                    Layout.fillWidth: true
                                    readOnly: true
                                    text: typeof backend !== "undefined" ? backend.getDbPath() : ""
                                    color: Theme.subText
                                }
                                WinButton {
                                    text: I18n.t("settings.openFolder", "Open Folder")
                                    Layout.preferredHeight: 38
                                    onClicked: { if (typeof backend !== "undefined") backend.openDbFolder() }
                                }
                                WinButton {
                                    text: I18n.t("settings.changeLocation", "Change Location")
                                    isAccent: true
                                    Layout.preferredHeight: 38
                                    onClicked: dbFolderDialog.open()
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: expCol.implicitHeight + 32
                        color: Theme.card
                        radius: 8
                        border.color: Theme.border

                        ColumnLayout {
                            id: expCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text { text: I18n.t("settings.export", "Export Telemetry Data"); font.pixelSize: 18; font.bold: true; color: Theme.text }
                            Text { text: I18n.t("settings.exportHelp", "Export saved sensor telemetry to a standard CSV file."); font.pixelSize: 14; color: Theme.subText; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16
                                Layout.topMargin: 4

                                ColumnLayout {
                                    spacing: 6
                                    Text { text: I18n.t("settings.timeRange", "TIME RANGE"); color: Theme.accent; font.pixelSize: 12; font.bold: true }
                                    ComboBox {
                                        id: exportRangeCombo
                                        Layout.preferredWidth: 200
                                        font.pixelSize: 14
                                        model: [I18n.t("ranges.hour", "Last 1 Hour"), I18n.t("ranges.day", "Last 24 Hours"), I18n.t("ranges.week", "Last 7 Days"), I18n.t("ranges.all", "All Data")]
                                        currentIndex: 1

                                        background: Rectangle {
                                            color: Theme.controlBg
                                            radius: 6
                                            border.color: exportRangeCombo.activeFocus ? Theme.accent : Theme.border
                                            border.width: exportRangeCombo.activeFocus ? 2 : 1
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                        }

                                        contentItem: Text {
                                            text: exportRangeCombo.displayText
                                            color: Theme.text
                                            font.pixelSize: 14
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 12
                                        }

                                        delegate: ItemDelegate {
                                            width: exportRangeCombo.width
                                            contentItem: Text { text: modelData; color: Theme.text; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
                                            background: Rectangle { color: exportRangeCombo.highlightedIndex === index ? Theme.controlHover : "transparent"; radius: 4 }
                                        }

                                        popup: Popup {
                                            y: exportRangeCombo.height + 4
                                            width: exportRangeCombo.width
                                            padding: 4
                                            background: Rectangle { color: Theme.dialog; border.color: Theme.border; radius: 6 }
                                            contentItem: ListView { clip: true; implicitHeight: contentHeight; model: exportRangeCombo.popup.visible ? exportRangeCombo.delegateModel : null; currentIndex: exportRangeCombo.highlightedIndex }
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                WinButton {
                                    Layout.alignment: Qt.AlignBottom
                                    text: Icons.download + "  " + I18n.t("settings.exportToCsv", "Export to CSV")
                                    isAccent: true
                                    Layout.preferredHeight: 38
                                    Layout.preferredWidth: 160
                                    onClicked: exportFileDialog.open()
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: abtCol.implicitHeight + 32
                        color: Theme.card
                        radius: 8
                        border.color: Theme.border

                        ColumnLayout {
                            id: abtCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text { text: I18n.t("settings.about", "About KAI Bridge Inspection"); font.pixelSize: 18; font.bold: true; color: Theme.text }
                            Text { text: I18n.t("settings.aboutBody", "Version: 1.0.0\nBuilt with Qt/QML and Python"); font.pixelSize: 14; color: Theme.subText; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                            WinButton {
                                text: I18n.t("settings.checkUpdates", "Check for Updates")
                                Layout.preferredWidth: 200
                                Layout.topMargin: 4
                                onClicked: console.log("Update check triggered")
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 24

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: nodeRedOwnership.implicitHeight + 32
                        color: Theme.card
                        radius: 8
                        border.color: Theme.border
                        ColumnLayout {
                            id: nodeRedOwnership
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10
                            Text { text: I18n.t("nodeRed.mqttOwnership", "MQTT ownership"); font.pixelSize: 18; font.bold: true; color: Theme.text }
                            Text {
                                text: I18n.t("nodeRed.mqttOwnershipHelp", "MQTT brokers, credentials, subscriptions, Sparkplug B decoding, aliases, birth/death state, and routing are configured exclusively in Node-RED. Use the Node-RED workspace page to set the host, then configure one dedicated WebSocket path for each sensor.")
                                font.pixelSize: 13
                                color: Theme.subText
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: devCol.implicitHeight + 32
                        color: Theme.card
                        radius: 8
                        border.color: Theme.border

                        ColumnLayout {
                            id: devCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text { text: I18n.t("settings.dataOptions", "Data Gathering & Options"); font.pixelSize: 18; font.bold: true; color: Theme.text }
                            Text { text: I18n.t("settings.dataOptionsHelp", "Manage background telemetry collection and developer logging."); font.pixelSize: 14; color: Theme.subText; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                            Switch {
                                id: gatheringSwitch
                                text: I18n.t("settings.backgroundCollection", "Enable Background Data Collection")
                                checked: typeof backend !== "undefined" ? (backend.getSetting("data_gathering", "true") === "true") : true

                                indicator: Rectangle {
                                    implicitWidth: 44
                                    implicitHeight: 24
                                    x: gatheringSwitch.leftPadding
                                    y: parent.height / 2 - height / 2
                                    radius: 12
                                    color: gatheringSwitch.checked ? Theme.accent : Theme.controlBg
                                    border.color: gatheringSwitch.checked ? Theme.accent : Theme.border
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Rectangle {
                                        x: gatheringSwitch.checked ? parent.width - width - 2 : 2
                                        y: 2
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: "white"
                                        border.color: "#33000000"
                                        border.width: 1
                                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
                                    }
                                }

                                contentItem: Text {
                                    text: gatheringSwitch.text
                                    font.pixelSize: 14
                                    color: Theme.text
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: gatheringSwitch.indicator.width + 12
                                }

                                onClicked: { if (typeof backend !== "undefined") backend.saveSetting("data_gathering", checked ? "true" : "false") }
                            }

                            Switch {
                                id: debugSwitch
                                text: I18n.t("settings.debugLogs", "Enable Console Debug Logs")
                                checked: typeof backend !== "undefined" ? backend.getDebugPrint() : false

                                indicator: Rectangle {
                                    implicitWidth: 44
                                    implicitHeight: 24
                                    x: debugSwitch.leftPadding
                                    y: parent.height / 2 - height / 2
                                    radius: 12
                                    color: debugSwitch.checked ? Theme.accent : Theme.controlBg
                                    border.color: debugSwitch.checked ? Theme.accent : Theme.border
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Rectangle {
                                        x: debugSwitch.checked ? parent.width - width - 2 : 2
                                        y: 2
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: "white"
                                        border.color: "#33000000"
                                        border.width: 1
                                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
                                    }
                                }

                                contentItem: Text {
                                    text: debugSwitch.text
                                    font.pixelSize: 14
                                    color: Theme.text
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: debugSwitch.indicator.width + 12
                                }

                                onClicked: { if (typeof backend !== "undefined") backend.setDebugPrint(checked) }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true } // Pushes content up
                }
            }
        }
    }

    FolderDialog {
        id: dbFolderDialog
        title: I18n.t("settings.selectDatabase", "Select New Database Folder")
        onAccepted: {
            if (typeof backend !== "undefined") {
                backend.setDbFolder(folder)
                dbPathField.text = backend.getDbPath()
            }
        }
    }

    FileDialog {
        id: exportFileDialog
        title: I18n.t("settings.saveCsv", "Save Exported CSV")
        fileMode: FileDialog.SaveFile
        nameFilters: ["CSV files (*.csv)"]
        onAccepted: {
            let filepath = selectedFile.toString().replace("file://", "")
            if (Qt.platform.os === "windows" && filepath.startsWith("/")) filepath = filepath.substring(1);

            let now = Date.now() / 1000
            let startTime = 0

            switch (exportRangeCombo.currentIndex) {
                case 0: startTime = now - 3600; break;
                case 1: startTime = now - (24 * 3600); break;
                case 2: startTime = now - (7 * 24 * 3600); break;
                default: startTime = 0; break;
            }

            if (typeof backend !== "undefined") backend.exportData(filepath, startTime, 0)
        }
    }
}
