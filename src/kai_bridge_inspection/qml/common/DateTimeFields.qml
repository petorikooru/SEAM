import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../"

RowLayout {
    id: fields

    component DateTimeNumber: SpinBox {
        id: numberField
        editable: true
        implicitHeight: 36
        implicitWidth: 112
        leftPadding: 32
        rightPadding: 32
        hoverEnabled: true

        contentItem: TextInput {
            text: numberField.displayText
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentText
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            validator: numberField.validator
            inputMethodHints: Qt.ImhDigitsOnly
        }

        down.indicator: DateTimeStep {
            x: 3
            y: 3
            height: numberField.height - 6
            iconName: Icons.minus
            available: numberField.value > numberField.from
            hovered: numberField.down.hovered
            pressed: numberField.down.pressed
        }

        up.indicator: DateTimeStep {
            x: numberField.width - width - 3
            y: 3
            height: numberField.height - 6
            iconName: Icons.plus
            available: numberField.value < numberField.to
            hovered: numberField.up.hovered
            pressed: numberField.up.pressed
        }

        background: Rectangle {
            radius: 8
            color: Theme.controlBg
            border.color: numberField.activeFocus ? Theme.accent : Theme.border
        }
    }

    component DateTimeStep: Rectangle {
        property string iconName
        property bool available
        property bool hovered
        property bool pressed
        width: 26
        radius: 5
        color: !available ? Theme.controlDisabled :
            pressed ? Theme.controlPressed : hovered ? Theme.controlHover : Theme.controlBg
        border.color: Theme.border

        LucideIcon {
            anchors.centerIn: parent
            icon: parent.iconName
            size: Theme.iconSizeSmall
            color: parent.available ? Theme.text : Theme.disabledText
        }
    }

    property date selectedDate: new Date()
    property string fieldName
    signal edited()

    function setDateTime(date) {
        selectedDate = date
        hours.value = date.getHours()
        minutes.value = date.getMinutes()
    }

    function value() {
        return Qt.formatDate(selectedDate, "yyyy-MM-dd") + " " +
            String(hours.value).padStart(2, "0") + ":" +
            String(minutes.value).padStart(2, "0") + ":00"
    }

    WinButton {
        id: dateButton
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignBottom
        text: Qt.formatDate(fields.selectedDate, "yyyy-MM-dd")
        Accessible.name: fields.fieldName + " " + text
        onClicked: calendar.open()

        Popup {
            id: calendar
            objectName: "dateTimeCalendar"
            y: dateButton.height + 4
            width: 292
            padding: 12
            focus: true
            property bool jumpVisible: false
            onAboutToShow: {
                jumpVisible = false
                days.month = fields.selectedDate.getMonth()
                days.year = fields.selectedDate.getFullYear()
            }
            background: Rectangle { color: Theme.dialog; radius: 10; border.color: Theme.border }
            contentItem: ColumnLayout {
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    WinButton {
                        text: I18n.t("common.previous", "Previous")
                        onClicked: {
                            const month = new Date(days.year, days.month - 1, 1)
                            days.year = month.getFullYear()
                            days.month = month.getMonth()
                        }
                    }
                    WinButton {
                        Layout.fillWidth: true
                        text: days.title
                        Accessible.name: I18n.t("sensor.chooseMonthYear", "Choose month and year")
                        onClicked: {
                            monthPicker.currentIndex = days.month
                            yearPicker.value = days.year
                            calendar.jumpVisible = !calendar.jumpVisible
                        }
                    }
                    WinButton {
                        text: I18n.t("common.next", "Next")
                        onClicked: {
                            const month = new Date(days.year, days.month + 1, 1)
                            days.year = month.getFullYear()
                            days.month = month.getMonth()
                        }
                    }
                }
                RowLayout {
                    visible: calendar.jumpVisible
                    Layout.fillWidth: true
                    WinComboBox {
                        id: monthPicker
                        Layout.fillWidth: true
                        model: Array.from({length: 12}, (_, i) => days.locale.standaloneMonthName(i))
                        Accessible.name: I18n.t("sensor.month", "Month")
                        onActivated: days.month = currentIndex
                    }
                    DateTimeNumber {
                        id: yearPicker
                        Layout.preferredWidth: 126
                        from: 1970
                        to: 2262
                        textFromValue: value => String(value)
                        Accessible.name: I18n.t("sensor.year", "Year")
                        onValueModified: days.year = value
                    }
                }
                DayOfWeekRow {
                    Layout.fillWidth: true
                    locale: days.locale
                    delegate: Text {
                        required property var model
                        text: model.shortName
                        color: Theme.subText
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                MonthGrid {
                    id: days
                    onMonthChanged: monthPicker.currentIndex = month
                    onYearChanged: yearPicker.value = year
                    Layout.fillWidth: true
                    Layout.preferredHeight: 204
                    spacing: 2
                    delegate: Button {
                        id: dayButton
                        required property var model
                        readonly property bool selected: enabled &&
                            Qt.formatDate(model.date, "yyyy-MM-dd") === dateButton.text
                        text: String(model.day)
                        enabled: model.month === days.month
                        padding: 0
                        contentItem: Text {
                            text: dayButton.text
                            color: dayButton.selected ? Theme.accentText :
                                dayButton.enabled ? Theme.text : Theme.mutedText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 6
                            color: dayButton.selected ? Theme.accent :
                                dayButton.hovered ? Theme.controlHover : Theme.controlBg
                            border.color: dayButton.activeFocus ? Theme.accent : Theme.border
                        }
                        Accessible.name: Qt.formatDate(model.date, Qt.locale().dateFormat(Locale.LongFormat))
                        onClicked: {
                            fields.selectedDate = model.date
                            calendar.close()
                            fields.edited()
                        }
                    }
                }
            }
        }
    }
    ColumnLayout {
        spacing: 4
        FieldLabel { labelText: I18n.t("sensor.hour", "Hour") }
        DateTimeNumber {
            id: hours
            from: 0
            to: 23
            textFromValue: value => String(value).padStart(2, "0")
            Accessible.name: fields.fieldName + " " + I18n.t("sensor.hour", "Hour")
            onValueModified: fields.edited()
        }
    }
    ColumnLayout {
        spacing: 4
        FieldLabel { labelText: I18n.t("sensor.minute", "Minute") }
        DateTimeNumber {
            id: minutes
            from: 0
            to: 59
            textFromValue: value => String(value).padStart(2, "0")
            Accessible.name: fields.fieldName + " " + I18n.t("sensor.minute", "Minute")
            onValueModified: fields.edited()
        }
    }
}
