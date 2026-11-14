import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../"

CheckBox {
    id: control

    property color seriesColor: Theme.accent

    implicitHeight: 28
    spacing: 6
    font.pixelSize: 12

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        radius: 4
        color: control.checked ? control.seriesColor : "transparent"
        border.color: control.checked ? control.seriesColor : Theme.borderLight
        border.width: 1

        LucideIcon {
            anchors.centerIn: parent
            icon: Icons.check
            size: 10
            color: control.checked ? Theme.accentText : "transparent"
        }
    }

    contentItem: Text {
        text: control.text
        color: control.checked ? Theme.text : Theme.subText
        font.pixelSize: 12
        leftPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
    }
}
