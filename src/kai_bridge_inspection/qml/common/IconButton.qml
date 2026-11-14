import QtQuick
import QtQuick.Controls
import "../"

Button {
    id: control

    property string iconText: ""
    property string tip: ""
    property color iconColor: Theme.text
    property color normalColor: Theme.controlBg
    property int buttonSize: 36
    property int iconPixelSize: Theme.iconSize

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    padding: 0
    hoverEnabled: true

    background: Rectangle {
        radius: 8
        color: control.down ? Theme.controlPressed : (control.hovered ? Theme.controlHover : control.normalColor)
        border.color: control.hovered || control.activeFocus ? Theme.borderLight : Theme.border
    }

    contentItem: Text {
        text: control.iconText
        font.family: Icons.fontFamily
        font.pixelSize: control.iconPixelSize
        color: control.enabled ? control.iconColor : Theme.disabledText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    ToolTip.visible: control.hovered && control.tip.length > 0
    ToolTip.text: control.tip
    ToolTip.delay: 350
}
