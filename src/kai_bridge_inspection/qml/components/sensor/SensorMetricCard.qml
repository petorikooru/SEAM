import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../"
import "../../common"

Rectangle {
    id: card

    property string labelText: ""
    property string valueText: "--"
    property string captionText: ""
    property string iconText: ""
    property bool showAction: false
    property string actionTip: ""
    signal actionRequested()

    Layout.fillWidth: true
    Layout.preferredHeight: 72
    color: Theme.card
    radius: 8
    border.color: Theme.border

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        LucideIcon {
            icon: card.iconText
            size: Theme.iconSize
            color: Theme.accent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: card.labelText
                color: Theme.subText
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: card.captionText.length > 0
                text: card.captionText
                color: Theme.mutedText
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Text {
            text: card.valueText
            color: Theme.text
            font.pixelSize: card.captionText.length > 0 ? 17 : 19
            font.bold: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            Layout.maximumWidth: 150
        }

        IconButton {
            visible: card.showAction
            buttonSize: 30
            iconPixelSize: Theme.iconSizeSmall
            iconText: Icons.chart
            iconColor: Theme.accent
            normalColor: "transparent"
            tip: card.actionTip
            onClicked: card.actionRequested()
        }
    }
}
