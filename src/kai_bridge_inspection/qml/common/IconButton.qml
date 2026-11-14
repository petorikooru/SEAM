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
    Accessible.name: tip

    background: Rectangle {
        radius: 8
        color: control.down ? Theme.controlPressed : (control.hovered ? Theme.controlHover : control.normalColor)
        border.color: control.visualFocus ? Theme.text : (control.hovered ? Theme.borderLight : Theme.border)
        border.width: control.visualFocus ? 2 : 1
    }

    contentItem: LucideIcon {
        icon: control.iconText
        size: control.iconPixelSize
        color: control.enabled ? control.iconColor : Theme.disabledText
    }

    ToolTip.visible: control.hovered && control.tip.length > 0
    ToolTip.text: control.tip
    ToolTip.delay: 350
}
