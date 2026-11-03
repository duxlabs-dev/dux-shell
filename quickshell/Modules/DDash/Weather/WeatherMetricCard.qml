pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import "WeatherVisuals.js" as Visuals

Rectangle {
    id: root

    property string widgetId: "humidity"
    property var widgetOptions: ({})
    readonly property var weather: WeatherService.weather
    readonly property bool graphics: widgetOptions.graphics !== false
    readonly property var reading: {
        SettingsData.useFahrenheit;
        SettingsData.windSpeedUnit;
        switch (widgetId) {
        case "humidity":
            return {
                label: I18n.tr("Humidity", "weather metric label"),
                icon: "humidity_low",
                value: WeatherService.formatPercent(weather.humidity),
                level: weather.humidity,
                detail: weather.dewPoint == null ? "" : I18n.tr("Dew point %1", "Weather dew point temperature").arg(WeatherService.formatTemp(weather.dewPoint))
            };
        case "wind":
            return {
                label: I18n.tr("Wind", "noun, weather wind speed metric label"),
                icon: "air",
                value: WeatherService.formatSpeed(weather.wind),
                shape: "arrow",
                detail: weather.windDirection == null ? "" : I18n.tr("From %1", "Weather wind origin, followed by a cardinal direction").arg(root.windDirection)
            };
        case "precipitation":
            return {
                label: I18n.tr("Precipitation", "weather precipitation probability metric label"),
                icon: "rainy",
                value: WeatherService.formatPercent(weather.precipitationProbability),
                level: weather.precipitationProbability,
                detail: I18n.tr("Today")
            };
        case "pressure":
            return {
                label: I18n.tr("Pressure", "weather atmospheric pressure metric label"),
                icon: "speed",
                value: WeatherService.formatPressure(weather.pressure, false),
                shape: "circle",
                detail: SettingsData.useFahrenheit ? "inHg" : "hPa"
            };
        case "visibility":
            return {
                label: I18n.tr("Visibility", "weather visibility distance metric", true),
                icon: "visibility",
                value: WeatherService.formatVisibility(weather.visibility),
                shape: "cookie12"
            };
        case "uv":
            return {
                label: I18n.tr("UV Index"),
                icon: "light_mode",
                value: weather.uv == null ? null : String(weather.uv),
                shape: "cookie7",
                detail: root.uvCategories[root.uvCategory] ?? ""
            };
        }
        return {};
    }
    readonly property var uvCategories: [I18n.tr("Low"), I18n.tr("Moderate", "uv index category"), I18n.tr("High"), I18n.tr("Very High"), I18n.tr("Extreme", "uv index category")]
    readonly property int uvCategory: Visuals.uvCategory(weather.uv)
    readonly property string windDirection: {
        const directions = [I18n.tr("N", "North compass direction"), I18n.tr("NE", "Northeast compass direction"), I18n.tr("E", "East compass direction"), I18n.tr("SE", "Southeast compass direction"), I18n.tr("S", "South compass direction"), I18n.tr("SW", "Southwest compass direction"), I18n.tr("W", "West compass direction"), I18n.tr("NW", "Northwest compass direction")];
        return directions[Visuals.directionIndex(weather.windDirection)] ?? "";
    }
    readonly property real shapeLevel: {
        if (!graphics || !weather.available)
            return 0;
        const hours = (weather.hourlyForecast ?? []).slice(0, 24);
        switch (widgetId) {
        case "pressure":
            return Visuals.relativeLevel(weather.pressure, hours.map(f => f.pressure), false);
        }
        return 1;
    }
    readonly property bool hasValue: weather.available && reading.value != null
    readonly property string graphicDescription: {
        if (!graphics || !hasValue)
            return "";
        switch (widgetId) {
        case "uv":
            return I18n.tr("The highlighted marker shows the UV category: low, moderate, high, very high, or extreme.");
        case "wind":
            if (Theme.shapeScale === 0)
                return I18n.tr("The direction label shows where the wind comes from.");
            return I18n.tr("The arrow points in the direction the wind is blowing. The label shows where it comes from.");
        case "humidity":
            return I18n.tr("The fill shows relative humidity. The badge shows the dew point temperature.");
        case "precipitation":
            return I18n.tr("The fill shows today's precipitation probability.");
        case "pressure":
            const values = (weather.hourlyForecast ?? []).slice(0, 24).map(f => f.pressure).filter(v => Number.isFinite(v));
            if (values.length === 0)
                return "";
            const minimum = Math.min(...values);
            const maximum = Math.max(...values);
            if (minimum === maximum)
                return I18n.tr("Today's pressure forecast is steady. The gauge stays at the midpoint.");
            return I18n.tr("Today's forecast pressure: %1 to %2. The gauge shows the current reading within that range.", "weather pressure card description, %1 is lowest, %2 highest pressure").arg(WeatherService.formatPressure(minimum)).arg(WeatherService.formatPressure(maximum));
        }
        return "";
    }
    readonly property color foreground: toneColors.contentColor
    readonly property color accent: toneColors.accentColor
    readonly property bool leadingContent: widgetId === "humidity" || widgetId === "precipitation"

    radius: graphics && reading.shape ? Theme.fullRadius(width, height) : Theme.cornerRadiusXL
    color: graphics && widgetId === "uv" ? "transparent" : toneColors.surfaceColor
    border.width: graphics && widgetId === "uv" ? 0 : Theme.layerOutlineWidth
    border.color: Theme.outlineMedium
    Accessible.role: Accessible.StaticText
    Accessible.name: reading.label + " " + (hasValue ? reading.value : I18n.tr("Not available")) + " " + (reading.detail ?? "")
    Accessible.description: graphicDescription

    DTone {
        id: toneColors
        tone: root.widgetOptions.tone ?? ""
    }

    StateLayer {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.ArrowCursor
        stateColor: "transparent"
        enableRipple: false
        tooltipText: root.graphicDescription
    }

    DMaterialShape {
        anchors.centerIn: parent
        readonly property real aspectRatio: root.widgetId === "wind" && Theme.shapeScale > 0 ? 17 / 20 : 1
        readonly property real artworkSize: Math.max(0, Math.min(parent.width, parent.height) - (root.widgetId === "uv" ? 0 : root.widgetId === "wind" ? Theme.spacingXS * 2 : Theme.spacingS * 2)) * (root.widgetId === "wind" && Theme.shapeScale > 0 ? rotationScaleForAspectRatio(aspectRatio) : 1)
        width: artworkSize * aspectRatio
        height: artworkSize
        shape: root.reading.shape ?? "square"
        color: root.widgetId === "uv" ? toneColors.surfaceColor : Theme.withAlpha(root.accent, Theme.stateLayerDrag)
        trackColor: Theme.withAlpha(root.accent, Theme.stateLayerHover)
        fillProgress: root.shapeLevel
        visible: root.graphics && !!root.reading.shape && root.widgetId !== "pressure"
        rotation: Theme.shapeScale > 0 && root.widgetId === "wind" && root.weather.windDirection != null ? (root.weather.windDirection + 180) % 360 : 0
    }

    Shape {
        anchors.fill: parent
        visible: root.graphics && root.hasValue && root.reading.level != null
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Theme.withAlpha(root.accent, Theme.stateLayerDrag)
            PathSvg {
                path: Visuals.levelPath(root.width, root.height, root.radius, (root.reading.level ?? 0) / 100, Theme.spacingS)
            }
        }
    }

    Item {
        id: content

        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width

        Shape {
            id: gauge

            anchors.fill: parent
            visible: root.graphics && root.widgetId === "pressure"
            preferredRendererType: Shape.CurveRenderer
            readonly property real thickness: Theme.spacingS
            readonly property real inset: Theme.spacingS + thickness / 2

            ShapePath {
                strokeColor: Theme.withAlpha(root.accent, Theme.stateLayerHover)
                strokeWidth: gauge.thickness
                capStyle: Theme.shapeScale > 0 ? ShapePath.RoundCap : ShapePath.FlatCap
                fillColor: "transparent"
                PathSvg {
                    path: Visuals.pressurePath(content.width, gauge.inset, 1, Theme.shapeScale === 0)
                }
            }

            ShapePath {
                strokeColor: root.hasValue && root.shapeLevel > 0 ? root.accent : "transparent"
                strokeWidth: gauge.thickness
                capStyle: Theme.shapeScale > 0 ? ShapePath.RoundCap : ShapePath.FlatCap
                fillColor: "transparent"
                PathSvg {
                    path: Visuals.pressurePath(content.width, gauge.inset, root.shapeLevel, Theme.shapeScale === 0)
                }
            }
        }

        Row {
            id: heading

            x: root.leadingContent ? (I18n.isRtl ? parent.width - width - Theme.spacingL : Theme.spacingL) : (parent.width - width) / 2
            anchors.bottom: value.top
            anchors.bottomMargin: Theme.spacingM
            width: Math.min(implicitWidth, parent.width - Theme.spacingXL * 2)
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.reading.icon ?? "cloud_off"
                size: Theme.iconSize
                color: root.foreground
            }

            StyledText {
                width: Math.min(implicitWidth, content.width - Theme.spacingXL * 2 - Theme.iconSize - heading.spacing)
                anchors.verticalCenter: parent.verticalCenter
                text: root.reading.label ?? ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: root.foreground
                elide: Text.ElideRight
            }
        }

        StyledText {
            id: value

            anchors.centerIn: parent
            width: Math.max(0, parent.width - Theme.spacingL * 2)
            height: Theme.fontSizeDisplay + Theme.spacingS
            text: root.hasValue ? root.reading.value : "--"
            font.pixelSize: Theme.fontSizeDisplay
            minimumPixelSize: Theme.fontSizeLarge
            fontSizeMode: Text.HorizontalFit
            font.weight: Theme.fontWeightMedium
            color: root.foreground
            horizontalAlignment: root.leadingContent ? Text.AlignLeft : Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        StyledText {
            anchors.top: value.bottom
            anchors.topMargin: Theme.spacingS
            anchors.horizontalCenter: parent.horizontalCenter
            width: value.width
            visible: text !== "" && !dewPoint.visible
            text: root.hasValue ? (root.reading.detail ?? "") : I18n.tr("Not available")
            font.pixelSize: Theme.fontSizeSmall
            color: root.foreground
            horizontalAlignment: root.leadingContent ? Text.AlignLeft : Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.graphics && root.widgetId === "uv" ? root.uvCategories.length : 0

            Rectangle {
                required property int index
                readonly property bool selected: root.hasValue && root.uvCategory === index
                readonly property real angle: (150 - (I18n.isRtl ? 4 - index : index) * 30) * Math.PI / 180
                readonly property real orbit: content.width / 2 - Theme.spacingXL
                readonly property var categoryColors: [Theme.success, Theme.warning, Theme.warning, Theme.error, Theme.tertiary]

                x: content.width / 2 + Math.cos(angle) * orbit - width / 2
                y: content.height / 2 + Math.sin(angle) * orbit - height / 2
                width: selected ? Theme.spacingL : Theme.spacingM
                height: width
                radius: Theme.fullRadius(width, height)
                color: selected ? categoryColors[index] : Theme.withAlpha(categoryColors[index], Theme.stateLayerDrag)
            }
        }

        Row {
            id: dewPoint

            x: I18n.isRtl ? parent.width - width - Theme.spacingL : Theme.spacingL
            anchors.top: value.bottom
            anchors.topMargin: Theme.spacingS
            spacing: Theme.spacingS
            visible: root.widgetId === "humidity" && root.hasValue && root.weather.dewPoint != null

            Rectangle {
                id: dewBadge

                width: Math.max(Theme.iconButtonSize, dewValue.implicitWidth + Theme.spacingM)
                height: Theme.iconButtonSize
                radius: Theme.fullRadius(width, height)
                color: toneColors.tinted ? toneColors.contentColor : Theme.primaryContainer

                StyledText {
                    id: dewValue

                    anchors.centerIn: parent
                    text: WeatherService.formatTemp(root.weather.dewPoint) ?? "--"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: toneColors.tinted ? toneColors.containerColor : Theme.onPrimaryContainer
                }
            }

            StyledText {
                width: Math.max(0, value.width - dewBadge.width - dewPoint.spacing)
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Dew point")
                font.pixelSize: Theme.fontSizeSmall
                color: root.foreground
                wrapMode: Text.WordWrap
            }
        }
    }
}
