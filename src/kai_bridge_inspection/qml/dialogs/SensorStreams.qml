import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../"
import "../common"

ColumnLayout {
    id: form

    property var profiles: ({})
    property string deviceId: ""
    property bool familyEditable: true
    readonly property bool beanDevice: family.currentIndex === 1
    readonly property string acquisition: beanDevice ? acquisitionMode.currentValue : ""
    readonly property string profile: family.currentIndex === 1
        ? "beandevice_" + mode.currentValue : family.currentValue
    readonly property bool custom: profile === "custom"
    readonly property string basePath: "kai/sensors/" + deviceId.trim().toLowerCase()
    property bool loading: false
    readonly property int motionStreamCount: acquisition === "streaming" ? 1 : (profiles[profile] || []).length

    function load(profile, streams, acquisition) {
        loading = true
        family.currentIndex = profile.indexOf("beandevice_") === 0 ? 1 : profile === "custom" ? 2 : 0
        mode.currentIndex = profile === "beandevice_inclinometer" ? 1 : profile === "beandevice_combo" ? 2 : 0
        acquisitionMode.currentIndex = acquisition === "streaming" ? 1 : 0
        loading = false
        setStreams(streams)
    }

    function resetMotionStreams() {
        const auxiliary = []
        if (beanDevice) {
            for (let i = 0; i < rows.count; ++i) {
                const row = rows.get(i)
                if (row.auxiliary)
                    auxiliary.push({metric: row.metric, path: row.path, edited: row.edited, auxiliary: true})
            }
        }
        setStreams([])
        for (const stream of auxiliary)
            rows.append(stream)
    }

    function setStreams(streams) {
        rows.clear()
        if (streams && streams.length) {
            const auxiliary = []
            for (const stream of streams) {
                const isAuxiliary = beanDevice && stream.metric !== "" && !(profiles[profile] || []).includes(stream.metric)
                const row = {metric: stream.metric, path: stream.path, edited: true, auxiliary: isAuxiliary}
                if (isAuxiliary)
                    auxiliary.push(row)
                else
                    rows.append(row)
            }
            for (const row of auxiliary)
                rows.append(row)
        } else {
            const metrics = custom || acquisition === "streaming" ? [""] : (profiles[profile] || [])
            for (const metric of metrics)
                rows.append({metric: metric, path: "", edited: false, auxiliary: false})
        }
    }

    function values() {
        const streams = []
        for (let i = 0; i < rows.count; ++i) {
            const editor = editors.itemAt(i)
            streams.push({metric: editor.metricValue, path: editor.pathValue})
        }
        return streams
    }

    onAcquisitionChanged: if (!loading && beanDevice && profiles[profile] !== undefined) resetMotionStreams()
    onProfileChanged: if (!loading && profiles[profile] !== undefined) resetMotionStreams()
    onProfilesChanged: if (!rows.count && profiles[profile] !== undefined) setStreams([])

    ListModel { id: rows }

    FieldLabel { visible: form.familyEditable; labelText: I18n.t("sensorStreams.family", "Sensor type") }
    WinComboBox {
        id: family
        visible: form.familyEditable
        Layout.fillWidth: true
        textRole: "text"
        valueRole: "value"
        model: [
            {text: "NemoSense", value: "nemosense"},
            {text: "BeanDevice", value: "beandevice"},
            {text: I18n.t("sensorStreams.custom", "Custom"), value: "custom"}
        ]
    }

    FieldLabel {
        visible: family.currentIndex === 1
        labelText: I18n.t("sensorStreams.mode", "BeanDevice channels")
    }
    WinComboBox {
        id: mode
        visible: family.currentIndex === 1
        Layout.fillWidth: true
        textRole: "text"
        valueRole: "value"
        model: [
            {text: I18n.t("sensorStreams.accelerometer", "Accelerometer"), value: "accelerometer"},
            {text: I18n.t("sensorStreams.inclinometer", "Inclinometer"), value: "inclinometer"},
            {text: I18n.t("sensorStreams.combo", "Combo"), value: "combo"}
        ]
    }

    FieldLabel {
        visible: form.beanDevice
        labelText: I18n.t("sensorStreams.acquisition", "Acquisition mode")
    }

    WinComboBox {
        id: acquisitionMode
        visible: form.beanDevice
        Layout.fillWidth: true
        textRole: "text"
        valueRole: "value"
        model: [
            {text: I18n.t("sensorStreams.periodic", "Periodic (Low Duty Cycle)"), value: "periodic"},
            {text: I18n.t("sensorStreams.streaming", "Streaming"), value: "streaming"}
        ]
    }

    FieldLabel { labelText: I18n.t("sensorStreams.paths", "Node-RED WebSocket paths") }

    Repeater {
        id: editors
        model: rows

        ColumnLayout {
            id: editor
            required property int index
            required property string metric
            required property string path
            required property bool edited
            required property bool auxiliary
            readonly property bool metricEditable: form.custom || auxiliary
            readonly property string metricValue: metricEditable ? metricField.text.trim() : metric
            readonly property string suggestedPath: metricEditable || !form.deviceId.trim() ? ""
                : form.acquisition === "streaming" ? form.deviceId.trim() + "/STREAMING"
                : form.beanDevice ? form.deviceId.trim() + "/SENSOR/" + channelIds[metric]
                : form.basePath
            readonly property var channelIds: ({"ACC/Z": 0, "ACC/X": 1, "ACC/Y": 2, "ACC/ROLL": 3, "ACC/PITCH": 4})
            readonly property string pathValue: pathField.text.trim()
            Layout.fillWidth: true

            FieldLabel {
                visible: editor.auxiliary && editor.index === form.motionStreamCount
                Layout.topMargin: 10
                labelText: I18n.t("sensorStreams.auxiliaryPaths", "Auxiliary WebSocket paths")
            }

            FieldLabel {
                visible: !editor.metricEditable && (editor.metric !== "" || form.acquisition === "streaming")
                labelText: editor.metric || I18n.t("sensorStreams.shared", "Shared channel stream")
            }

            function focusMetric() {
                metricField.forceActiveFocus(Qt.TabFocusReason)
            }

            GridLayout {
                Layout.fillWidth: true
                columns: editor.auxiliary ? 2 : 3

                WinTextField {
                    id: metricField
                    visible: editor.metricEditable
                    Layout.columnSpan: editor.auxiliary ? 2 : 1
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Accessible.name: placeholderText
                    placeholderText: I18n.t("sensorStreams.metric", "Metric name")
                    text: editor.metric
                    onTextEdited: rows.setProperty(editor.index, "metric", text)
                }

                WinTextField {
                    id: pathField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Accessible.name: I18n.t("sensorStreams.paths", "Node-RED WebSocket paths")
                    placeholderText: "kai/sensors/device/metric"
                    text: editor.edited ? editor.path : editor.suggestedPath
                    onTextEdited: {
                        rows.setProperty(editor.index, "path", text)
                        rows.setProperty(editor.index, "edited", true)
                    }
                }

                WinButton {
                    visible: editor.auxiliary || (form.custom && rows.count > 1)
                    iconName: Icons.trash
                    text: I18n.t("common.delete", "Delete")
                    Accessible.name: editor.metricValue ? text + " " + editor.metricValue : text
                    onClicked: {
                        addMetricButton.forceActiveFocus(Qt.TabFocusReason)
                        rows.remove(editor.index)
                    }
                }
            }
        }
    }

    WinButton {
        id: addMetricButton
        visible: form.custom || form.beanDevice
        iconName: Icons.add
        text: form.beanDevice ? I18n.t("sensorStreams.addAuxiliary", "Add auxiliary metric")
                             : I18n.t("sensorStreams.addMetric", "Add metric")
        onClicked: {
            rows.append({metric: "", path: "", edited: false, auxiliary: form.beanDevice})
            const editor = editors.itemAt(rows.count - 1)
            if (editor)
                editor.focusMetric()
        }
    }
}
