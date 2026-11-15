import QtQuick
import QtQuick.Layouts
import "../../"

GridLayout {
    id: grid

    property string temperature: "-- °C"
    property string battery: "-- %"
    property string sampleRate: "-- Hz"
    property string signalLabel: "--"
    property string rssi: "-- dBm"
    property string chargerStatus: "--"
    property string powerSource: "--"
    property string mqttStatus: "--"
    property string ntpStatus: "--"
    property string lostSamples: "--"
    property string latency: "--"

    readonly property string signalState: signalLabel.trim().toLowerCase()
    readonly property color signalColor: ["lost", "bad", "down", "offline"].includes(signalState) ? Theme.danger
        : ["excellent", "good"].includes(signalState) ? Theme.success
        : ["ok", "fair", "weak"].includes(signalState) ? Theme.warning : Theme.subText

    signal batteryHistoryRequested()

    Layout.fillWidth: true
    columns: width > 1150 ? 4 : (width > 650 ? 2 : 1)
    columnSpacing: 12
    rowSpacing: 12

    SensorMetricCard {
        labelText: I18n.t("sensor.temperature", "Temperature")
        valueText: grid.temperature
        iconText: Icons.temp
    }
    SensorMetricCard {
        labelText: I18n.t("sensor.battery", "Battery")
        valueText: grid.battery
        iconText: Icons.battery
        showAction: true
        actionTip: I18n.t("sensor.batteryGraph", "Battery graph")
        onActionRequested: grid.batteryHistoryRequested()
    }
    SensorMetricCard {
        labelText: I18n.t("sensor.sampleRate", "Sample Rate")
        valueText: grid.sampleRate
        iconText: Icons.sampleRate
    }
    SensorMetricCard {
        labelText: I18n.t("sensor.signal", "Signal")
        valueText: grid.signalLabel
        captionText: grid.rssi
        iconText: Icons.signal
        iconColor: grid.signalColor
        valueColor: grid.signalColor
    }
    SensorMetricCard {
        labelText: I18n.t("sensor.charger", "Charger")
        valueText: grid.chargerStatus
        captionText: grid.powerSource
        iconText: Icons.plug
    }
    SensorMetricCard {
        labelText: I18n.t("sensor.deviceLink", "Device Link")
        valueText: grid.mqttStatus
        captionText: "NTP " + grid.ntpStatus
        iconText: Icons.connection
    }
    SensorMetricCard {
        labelText: I18n.t("sensor.dataLoss", "Data Loss")
        valueText: grid.lostSamples
        captionText: I18n.format("sensor.latency", {"value": grid.latency}, "latency " + grid.latency)
        iconText: Icons.warning
    }
}
