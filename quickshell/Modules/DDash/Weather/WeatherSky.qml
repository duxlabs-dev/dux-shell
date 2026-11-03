import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

Rectangle {
    id: root

    property bool live: Window.window?.visible ?? false
    property bool moon: false
    property var widgetOptions: ({})
    property var currentDate: new Date()
    readonly property var sunTimes: live && !moon ? WeatherService.getSunTimes(currentDate) : null
    readonly property var moonTrack: live && moon ? WeatherService.getMoonTrack(currentDate) : null
    readonly property string riseText: moon ? (WeatherService.weather.moonrise ? WeatherService.formatTime(WeatherService.weather.moonrise) : "--") : (hasSunTimes ? WeatherService.formatTime(sunTimes.sunrise) : "--")
    readonly property string setText: moon ? (WeatherService.weather.moonset ? WeatherService.formatTime(WeatherService.weather.moonset) : "--") : (hasSunTimes ? WeatherService.formatTime(sunTimes.sunset) : "--")
    readonly property real sunriseTime: sunTimes?.sunrise?.getTime() ?? NaN
    readonly property real sunsetTime: sunTimes?.sunset?.getTime() ?? NaN
    readonly property bool hasSunTimes: Number.isFinite(sunriseTime) && Number.isFinite(sunsetTime) && sunsetTime > sunriseTime
    readonly property real dayProgress: hasSunTimes ? Math.max(0, Math.min(1, (currentDate.getTime() - sunriseTime) / (sunsetTime - sunriseTime))) : 0

    function reset() {
        currentDate = new Date();
    }

    onLiveChanged: {
        if (live)
            reset();
    }

    readonly property var serviceWeather: WeatherService.weather

    onServiceWeatherChanged: {
        if (!live)
            return;
        reset();
    }

    implicitHeight: DashMetrics.gridRowUnit * 2 + DashMetrics.gridGap
    radius: Theme.cornerRadiusXL
    color: toneColors.surfaceColor
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium

    DTone {
        id: toneColors
        tone: root.widgetOptions.tone ?? ""
    }

    Row {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        DIcon {
            name: root.moon ? "dark_mode" : "light_mode"
            size: Theme.iconSize
            color: toneColors.contentColor
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.moon ? I18n.tr("Moon", "Weather moon position widget title") : I18n.tr("Sun", "Weather daylight widget title")
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
            color: toneColors.contentColor
        }
    }

    Item {
        id: arc
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: times.top
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingL
        anchors.topMargin: Theme.spacingL + Theme.iconSize + Theme.spacingS
        anchors.bottomMargin: Theme.spacingM
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Shape {
            anchors.fill: parent
            visible: !root.moon
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.withAlpha(toneColors.accentColor, Theme.stateLayerDrag)
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0
                startY: arc.height
                PathQuad {
                    x: arc.width
                    y: arc.height
                    controlX: arc.width / 2
                    controlY: -arc.height
                }
                PathLine {
                    x: 0
                    y: arc.height
                }
            }
        }

        Rectangle {
            y: root.moon ? parent.height / 2 : parent.height - height
            width: parent.width
            height: Theme.dividerWidth
            color: Theme.outlineVariant
        }

        DMaterialShape {
            readonly property real progress: I18n.isRtl ? 1 - root.dayProgress : root.dayProgress
            x: arc.width * progress - width / 2
            y: arc.height * (1 - 4 * progress * (1 - progress)) - height / 2
            width: Theme.iconSize
            height: width
            shape: "sunny"
            color: toneColors.accentColor
            visible: !root.moon && root.hasSunTimes && root.currentDate.getTime() >= root.sunriseTime && root.currentDate.getTime() <= root.sunsetTime
        }

        DSparkline {
            anchors.fill: parent
            visible: root.moon
            values: I18n.isRtl ? (root.moonTrack?.values ?? []).slice().reverse() : (root.moonTrack?.values ?? [])
            minimum: -1
            maximum: 1
            insetTop: 0
            insetBottom: 0
            lineWidth: Theme.outlineWidth
            lineColor: toneColors.accentColor
            fillOpacity: Theme.stateLayerDrag
        }

        DNFIcon {
            readonly property real progress: root.moonTrack?.progress ?? 0
            x: arc.width * (I18n.isRtl ? 1 - progress : progress) - width / 2
            y: arc.height * (1 - (root.moonTrack?.altitude ?? 0)) / 2 - height / 2
            name: WeatherService.getMoonPhase(root.currentDate)
            size: Theme.iconSize
            color: toneColors.accentColor
            visible: root.moon && root.moonTrack !== null
        }
    }

    Row {
        id: times
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Theme.spacingXS
            StyledText {
                width: parent.width
                text: root.moon ? I18n.tr("Moonrise", "Weather moonrise time") : I18n.tr("Sunrise")
                color: toneColors.mutedColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
            StyledText {
                width: parent.width
                text: root.riseText
                color: toneColors.contentColor
                font.pixelSize: Theme.fontSizeMedium
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
            }
        }

        Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Theme.spacingXS
            StyledText {
                width: parent.width
                text: root.moon ? I18n.tr("Moonset", "Weather moonset time") : I18n.tr("Sunset")
                color: toneColors.mutedColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignRight
            }
            StyledText {
                width: parent.width
                text: root.setText
                color: toneColors.contentColor
                font.pixelSize: Theme.fontSizeMedium
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
