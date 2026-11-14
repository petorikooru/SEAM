import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../"
import "../../common"

Rectangle {
    id: panel

    default property alias chartData: chartHost.data

    property string titleText: ""
    property string subtitleText: ""
    property string iconText: Icons.chart
    property color iconColor: Theme.info
    property var seriesModel: []
    property bool frozen: false
    property bool panMode: true

    signal freezeToggled()
    signal panModeToggled()
    signal resetRequested()
    signal seriesToggled(int index, bool checked)

    readonly property int responsiveMinimumHeight: width < 360 ? 610 : (width < 540 ? 560 : 520)

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: 0
    Layout.minimumHeight: responsiveMinimumHeight
    color: Theme.card
    radius: 10
    border.color: Theme.border

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerGrid.implicitHeight + 22
            radius: 9
            color: Theme.controlBg
            border.color: Theme.border

            GridLayout {
                id: headerGrid
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                columns: panel.width >= 540 ? 2 : 1
                columnSpacing: 12
                rowSpacing: 7

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 8
                        color: Qt.rgba(panel.iconColor.r, panel.iconColor.g, panel.iconColor.b, 0.14)
                        LucideIcon {
                            anchors.centerIn: parent
                            icon: panel.iconText
                            color: panel.iconColor
                            size: Theme.iconSize
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: panel.titleText
                            color: Theme.text
                            font.pixelSize: 16
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: panel.subtitleText
                            color: Theme.subText
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: 7

                    Text {
                        visible: panel.width >= 620
                        text: I18n.t("common.visibleSeries", "VISIBLE SERIES")
                        color: Theme.mutedText
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 0.6
                    }

                    Repeater {
                        model: panel.seriesModel
                        delegate: SeriesToggle {
                            required property int index
                            required property var modelData
                            text: modelData.label
                            seriesColor: modelData.color
                            checked: modelData.visible !== false
                            onToggled: panel.seriesToggled(index, checked)
                        }
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            WinButton {
                width: 118
                height: 34
                iconName: panel.frozen ? Icons.play : Icons.pause
                text: panel.frozen ? I18n.t("common.resume", "Resume") : I18n.t("common.freeze", "Freeze")
                isDanger: panel.frozen
                onClicked: panel.freezeToggled()
            }

            WinButton {
                width: 104
                height: 34
                iconName: panel.panMode ? Icons.hand : Icons.pinPoint
                text: panel.panMode ? I18n.t("common.pan", "Pan") : I18n.t("common.select", "Select")
                isAccent: !panel.panMode
                enabled: panel.frozen
                onClicked: panel.panModeToggled()
            }

            WinButton {
                width: 104
                height: 34
                iconName: Icons.refresh; text: I18n.t("common.reset", "Reset")
                enabled: panel.frozen
                onClicked: panel.resetRequested()
            }
        }

        Text {
            Layout.fillWidth: true
            text: panel.frozen ? I18n.t("sensor.chartInteractive", "Interactive navigation enabled") : I18n.t("sensor.chartLive", "Live follow mode")
            color: panel.frozen ? Theme.accent : Theme.mutedText
            font.pixelSize: 10
            visible: panel.width >= 420
            horizontalAlignment: Text.AlignRight
        }

        Item {
            id: chartHost
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 360
            clip: true
        }
    }
}
