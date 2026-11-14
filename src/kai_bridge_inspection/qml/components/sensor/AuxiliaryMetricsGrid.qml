import QtQuick
import QtQuick.Layouts
import "../../"
import "../../common"

GridLayout {
    id: grid
    property var streams: []
    property var auxiliaryValues: ({})
    readonly property var additionalMetrics: (grid.streams || [])
        .map(stream => stream.metric)
        .filter(metric => metric && ![
            "ACC/X", "ACC/Y", "ACC/Z", "ACC/ROLL", "ACC/PITCH",
            "ACC/TEMPERATURE", "TEMPERATURE", "temp", "temperature",
            "BATTERY", "BAT_FUEL_GAUGE_REPSOC", "battery",
            "CELLULAR_RSSI", "SIGNAL", "RSSI", "cellular_rssi",
            "INFERRED_SAMPLE_RATE", "inferred_sample_rate", "infered_sample_rate",
            "SIGNAL_STRENGTH_LABEL", "signal_strength_label", "BAT_CHARGER_STATUS_LABEL",
            "BATTERY_CHARGER_LABEL", "POWER_SOURCE_LABEL", "MQTT_DEVICE_STATUS",
            "MQTT_IS_CONNECTION_OK", "NTP_STATUS", "NTP_IS_CONNECTION_OK",
            "ACC_LOST_SAMPLES_COUNT", "DATA_LATENCY_SECONDS"
        ].includes(metric))

    function updateValues(data, replaceMissing) {
        const values = replaceMissing ? Object.create(null) : Object.assign(Object.create(null), auxiliaryValues)
        let changed = replaceMissing
        for (const metric of additionalMetrics) {
            if (Object.prototype.hasOwnProperty.call(data, metric)) {
                values[metric] = data[metric]
                changed = true
            }
        }
        if (changed)
            auxiliaryValues = values
    }

    visible: grid.additionalMetrics.length > 0
    Layout.fillWidth: true
    columns: width > 1150 ? 4 : (width > 650 ? 2 : 1)
    columnSpacing: 12
    rowSpacing: 12

    FieldLabel {
        Layout.columnSpan: grid.columns
        labelText: I18n.t("sensor.additionalMetrics", "Additional metrics")
    }

    Repeater {
        model: grid.additionalMetrics
        SensorMetricCard {
            required property string modelData
            labelText: modelData
            valueText: String(grid.auxiliaryValues[modelData] ?? "—")
            iconText: Icons.chart
        }
    }
}
