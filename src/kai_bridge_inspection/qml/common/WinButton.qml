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

    property string iconName: ""

    implicitHeight: 40
    leftPadding: 14
    rightPadding: 14
    hoverEnabled: true

    contentItem: Item {
        implicitWidth: buttonContent.implicitWidth
        implicitHeight: buttonContent.implicitHeight

        RowLayout {
            id: buttonContent
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width)
            spacing: 8

            LucideIcon {
                visible: control.iconName !== ""
                icon: control.iconName
                size: Theme.iconSize
                color: label.color
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                id: label
                visible: control.text !== ""
                text: control.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: control.isAccent
                color: !control.enabled ? Theme.disabledText :
                       control.isAccent ? Theme.accentText :
                       control.isDanger ? (control.hovered ? "white" : Theme.danger) : Theme.text
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            }
        }
    }

    background: Rectangle {
        radius: control.cornerRadius
        border.color: control.visualFocus ? Theme.text :
                      control.isAccent || control.isQuiet ? "transparent" :
                      control.isDanger ? Theme.danger : Theme.border
        border.width: control.visualFocus ? 2 : control.isAccent || control.isQuiet ? 0 : 1

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
