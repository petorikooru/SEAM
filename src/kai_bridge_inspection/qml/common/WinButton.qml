import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../"

Button {
    id: control

    property bool isAccent: false
    property bool isDanger: false
    property bool isQuiet: false
    property int cornerRadius: 8

    property string _iconChar: control.text.length > 0 && control.text.charCodeAt(0) >= 0xE000 ? control.text.charAt(0) : ""
    property string _labelText: control.text.length > 0 && control.text.charCodeAt(0) >= 0xE000 ? control.text.substring(1).trim() : control.text

    implicitHeight: 40
    leftPadding: 14
    rightPadding: 14
    hoverEnabled: true

    contentItem: RowLayout {
        spacing: 8

        Text {
            visible: control._iconChar !== ""
            text: control._iconChar
            font.family: Icons.fontFamily
            font.pixelSize: Theme.iconSize
            color: label.color
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            id: label
            visible: control._labelText !== ""
            text: control._labelText
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: control.isAccent
            color: !control.enabled ? Theme.disabledText :
                   control.isAccent ? Theme.accentText :
                   control.isDanger ? (control.hovered ? "white" : Theme.danger) : Theme.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        }
    }

    background: Rectangle {
        radius: control.cornerRadius
        border.color: control.isAccent || control.isQuiet ? "transparent" :
                      control.isDanger ? Theme.danger : Theme.border
        border.width: control.isAccent || control.isQuiet ? 0 : 1

        color: {
            if (!control.enabled) return Theme.controlDisabled
            if (control.isAccent) return control.down ? Theme.accentPressed : (control.hovered ? Theme.accentHover : Theme.accent)
            if (control.isDanger) return control.down ? Theme.dangerPressed : (control.hovered ? Theme.danger : "transparent")
            if (control.isQuiet) return control.down ? Theme.controlPressed : (control.hovered ? Theme.controlHover : "transparent")
            return control.down ? Theme.controlPressed : (control.hovered ? Theme.controlHover : Theme.controlBg)
        }

        Behavior on color { ColorAnimation { duration: 110 } }
    }
}
