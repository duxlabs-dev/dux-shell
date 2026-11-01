pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "../Common/suncalc.js" as SunCalc

Singleton {
    id: root
    readonly property var log: Log.scoped("WeatherService")

    property int refCount: 0

    property var selectedDate: new Date()
    property var weather: emptyWeather()

    function emptyWeather() {
        return {
            "available": false,
            "loading": true,
            "temp": 0,
            "tempF": 0,
            "feelsLike": 0,
            "feelsLikeF": 0,
            "city": "",
            "country": "",
            "wCode": 0,
            "humidity": 0,
            "wind": "",
            "sunrise": "06:00",
            "sunset": "18:00",
            "uv": 0,
            "pressure": 0,
            "precipitationProbability": 0,
            "isDay": true,
            "forecast": []
        };
    }

    property var location: null
    property int updateInterval: 900000 // 15 minutes
    property int retryAttempts: 0
    property int maxRetryAttempts: 3
    property int retryDelay: 30000
    property int lastFetchTime: 0
    property int minFetchInterval: 30000
    property int persistentRetryCount: 0
    property int _geocodeReqId: 0
    property var _pendingCoords: null

    // ionice is util-linux only; the BSDs get plain nice
    readonly property var lowPriorityCmd: Qt.platform.os === "linux" ? ["nice", "-n", "19", "ionice", "-c3"] : ["nice", "-n", "19"]
    readonly property var fetchCmd: [Proc.dmsBin, "dl", "--connect-timeout", "8", "--timeout", "20"]

    property var weatherIcons: ({
            "0": "clear_day",
            "1": "clear_day",
            "2": "partly_cloudy_day",
            "3": "cloud",
            "45": "foggy",
            "48": "foggy",
            "51": "rainy",
            "53": "rainy",
            "55": "rainy",
            "56": "rainy",
            "57": "rainy",
            "61": "rainy",
            "63": "rainy",
            "65": "rainy",
            "66": "rainy",
            "67": "rainy",
            "71": "cloudy_snowing",
            "73": "cloudy_snowing",
            "75": "snowing_heavy",
            "77": "cloudy_snowing",
            "80": "rainy",
            "81": "rainy",
            "82": "rainy",
            "85": "cloudy_snowing",
            "86": "snowing_heavy",
            "95": "thunderstorm",
            "96": "thunderstorm",
            "99": "thunderstorm"
        })

    readonly property var nightWeatherIcons: Object.assign({}, weatherIcons, {
        "0": "clear_night",
        "1": "clear_night",
        "2": "partly_cloudy_night"
    })

    function getWeatherIcon(code, isDay) {
        if (typeof isDay === "undefined") {
            isDay = weather.isDay;
        }
        const iconMap = isDay ? weatherIcons : nightWeatherIcons;
        return iconMap[String(code)] || "cloud";
    }

    function getWeatherCondition(code) {
        const conditions = {
            "0": I18n.tr("Clear Sky"),
            "1": I18n.tr("Clear Sky"),
            "2": I18n.tr("Partly Cloudy"),
            "3": I18n.tr("Overcast", "weather condition name"),
            "45": I18n.tr("Fog", "weather condition name"),
            "48": I18n.tr("Fog"),
            "51": I18n.tr("Drizzle", "weather condition name"),
            "53": I18n.tr("Drizzle"),
            "55": I18n.tr("Drizzle"),
            "56": I18n.tr("Freezing Drizzle"),
            "57": I18n.tr("Freezing Drizzle"),
            "61": I18n.tr("Light Rain"),
            "63": I18n.tr("Rain", "noun, weather condition name"),
            "65": I18n.tr("Heavy Rain"),
            "66": I18n.tr("Light Rain"),
            "67": I18n.tr("Heavy Rain"),
            "71": I18n.tr("Light Snow"),
            "73": I18n.tr("Snow", "noun, weather condition name"),
            "75": I18n.tr("Heavy Snow"),
            "77": I18n.tr("Snow"),
            "80": I18n.tr("Light Rain"),
            "81": I18n.tr("Rain"),
            "82": I18n.tr("Heavy Rain"),
            "85": I18n.tr("Light Snow Showers"),
            "86": I18n.tr("Heavy Snow Showers"),
            "95": I18n.tr("Thunderstorm", "weather condition name"),
            "96": I18n.tr("Thunderstorm with Hail"),
            "99": I18n.tr("Thunderstorm with Hail")
        };
        return conditions[String(code)] || I18n.tr("Unknown");
    }

    property var moonPhaseNames: ["moon_new", "moon_waxing_crescent", "moon_first_quarter", "moon_waxing_gibbous", "moon_full", "moon_waning_gibbous", "moon_last_quarter", "moon_waning_crescent"]

    function getMoonPhase(date) {
        const phases = moonPhaseNames;
        const iconCount = phases.length;
        const moon = SunCalc.getMoonIllumination(date);
        const index = ((Math.floor(moon.phase * iconCount + 0.5) % iconCount) + iconCount) % iconCount;

        return phases[index];
    }

    function getMoonAngle(date) {
        if (!location) {
            return;
        }
        const pos = SunCalc.getMoonPosition(date, location.latitude, location.longitude);
        return pos.parralacticAngle;
    }

    function getLocation() {
        return location;
    }

    function getSunDeclination(date) {
        return SunCalc.sunCoords(SunCalc.toDays(date)).dec * 180 / Math.PI;
    }

    function getSunTimes(date) {
        if (!location) {
            return null;
        }
        return SunCalc.getTimes(date, location.latitude, location.longitude, location.elevation);
    }

    function getMoonTrack(date) {
        if (!location)
            return null;
        const offset = (weather.utcOffsetSeconds ?? -date.getTimezoneOffset() * 60) * 1000;
        const localDate = new Date(date.getTime() + offset);
        const start = Date.UTC(localDate.getUTCFullYear(), localDate.getUTCMonth(), localDate.getUTCDate()) - offset;
        const hour = 60 * 60 * 1000;
        const altitude = time => Math.sin(SunCalc.getMoonPosition(new Date(time), location.latitude, location.longitude).altitude);
        const values = [];
        for (let i = 0; i <= 24; i++)
            values.push(altitude(start + i * hour));
        return {
            values: values,
            altitude: altitude(date.getTime()),
            progress: (date.getTime() - start) / (24 * hour)
        };
    }

    function getEcliptic(date, points = 60) {
        if (!location) {
            return null;
        }
        const lat = location.latitude;
        const lon = location.longitude;
        const times = SunCalc.getTimes(date, lat, lon);
        const solarNoon = times.solarNoon;

        const eclipticPoints = [];

        const sunIsNorth = getSunDeclination(date) > lat;
        const transitAzimuth = sunIsNorth ? 0 : Math.PI;

        for (let i = 0; i <= points; i++) {
            const t = new Date(solarNoon.getTime() + (i / points) * 24 * 60 * 60 * 1000);
            const pos = SunCalc.getPosition(t, lat, lon);

            let h = (((pos.azimuth - transitAzimuth) / (2 * Math.PI)) + 1) % 1;
            h = Math.max(0, Math.min(1, h));
            let v = Math.sin(pos.altitude);
            v = Math.max(-1, Math.min(1, v));

            eclipticPoints.push({
                h,
                v
            });
        }

        const sortedEntries = eclipticPoints.sort((a, b) => a.h - b.h);
        return sortedEntries;
    }

    function getCurrentSunTime(date) {
        const times = getSunTimes(date);
        if (!times) {
            return;
        }
        const dateObj = new Date(date);

        const periods = [
            {
                name: I18n.tr("Dawn (Astronomical Twilight)"),
                start: new Date(times.nightEnd),
                end: new Date(times.nauticalDawn)
            },
            {
                name: I18n.tr("Dawn (Nautical Twilight)"),
                start: new Date(times.nauticalDawn),
                end: new Date(times.dawn)
            },
            {
                name: I18n.tr("Dawn (Civil Twilight)"),
                start: new Date(times.dawn),
                end: new Date(times.sunrise)
            },
            {
                name: I18n.tr("Sunrise"),
                start: new Date(times.sunrise),
                end: new Date(times.sunriseEnd)
            },
            {
                name: I18n.tr("Golden Hour"),
                start: new Date(times.sunriseEnd),
                end: new Date(times.goldenHourEnd)
            },
            {
                name: I18n.tr("Morning", "time of day period name in weather view"),
                start: new Date(times.goldenHourEnd),
                end: new Date(times.solarNoon)
            },
            {
                name: I18n.tr("Afternoon", "time of day period name in weather view"),
                start: new Date(times.solarNoon),
                end: new Date(times.goldenHour)
            },
            {
                name: I18n.tr("Golden Hour"),
                start: new Date(times.goldenHour),
                end: new Date(times.sunsetStart)
            },
            {
                name: I18n.tr("Sunset"),
                start: new Date(times.sunsetStart),
                end: new Date(times.sunset)
            },
            {
                name: I18n.tr("Dusk (Civil Twighlight)"),
                start: new Date(times.sunset),
                end: new Date(times.dusk)
            },
            {
                name: I18n.tr("Dusk (Nautical Twilight)"),
                start: new Date(times.dusk),
                end: new Date(times.nauticalDusk)
            },
            {
                name: I18n.tr("Dusk (Astronomical Twilight)"),
                start: new Date(times.nauticalDusk),
                end: new Date(times.night)
            },
        ];

        const sunrise = new Date(times.nightEnd);
        const sunset = new Date(times.night);
        const dayPercent = dateObj > sunrise && dateObj < sunset ? (dateObj - sunrise) / (sunset - sunrise) : 0;

        for (let i = 0; i < periods.length; i++) {
            const {
                name,
                start,
                end
            } = periods[i];
            if (dateObj >= start && dateObj < end) {
                const percent = (dateObj - start) / (end - start);
                return {
                    period: name,
                    periodIndex: i,
                    periodPercent: Math.min(Math.max(percent, 0), 1),
                    dayPercent: dayPercent
                };
            }
        }

        return {
            period: I18n.tr("Night", "noun, time of day period, also night mode state"),
            periodIndex: 0,
            periodPercent: 0,
            dayPercent: dayPercent
        };
    }

    function getSkyArcPosition(date, isSun) {
        if (!location) {
            return null;
        }
        const lat = location.latitude;
        const lon = location.longitude;

        const pos = isSun ? SunCalc.getPosition(date, lat, lon) : SunCalc.getMoonPosition(date, lat, lon);

        const sunIsNorth = getSunDeclination(date) > lat;
        const transitAzimuth = sunIsNorth ? 0 : Math.PI;

        let h = (((pos.azimuth - transitAzimuth) / (2 * Math.PI)) + 1) % 1;
        h = Math.max(0, Math.min(1, h));
        // let v = pos.altitude / (Math.PI/2)
        let v = Math.sin(pos.altitude);
        v = Math.max(-1, Math.min(1, v));

        return {
            h,
            v
        };
    }

    function formatTemp(celsius, includeUnits = true, unitsShort = true) {
        if (celsius == null) {
            return null;
        }
        const value = SettingsData.useFahrenheit ? Math.round(celsius * (9 / 5) + 32) : celsius;
        const unit = unitsShort ? "°" : (SettingsData.useFahrenheit ? "°F" : "°C");
        return includeUnits ? value + unit : value;
    }

    function currentTempText(unitsShort = true) {
        const unit = unitsShort ? "°" : (SettingsData.useFahrenheit ? "°F" : "°C");
        if (!weather.available)
            return "--" + unit;
        return (SettingsData.useFahrenheit ? weather.tempF : weather.temp) + unit;
    }

    function formatSpeed(kmh, includeUnits = true) {
        if (kmh == null) {
            return null;
        }
        if (SettingsData.useFahrenheit) {
            const value = Math.round(kmh * 0.621371);
            return includeUnits ? value + " mph" : value;
        }
        if (SettingsData.windSpeedUnit === "ms") {
            const value = (kmh / 3.6).toFixed(1);
            return includeUnits ? value + " m/s" : value;
        }
        return includeUnits ? kmh + " km/h" : kmh;
    }

    function formatPressure(hpa, includeUnits = true) {
        if (hpa == null) {
            return null;
        }
        const value = SettingsData.useFahrenheit ? (hpa * 0.02953).toFixed(2) : hpa;
        const unit = SettingsData.useFahrenheit ? "inHg" : "hPa";
        return includeUnits ? value + " " + unit : value;
    }

    function formatPercent(percent, includeUnits = true) {
        if (percent == null) {
            return null;
        }
        const value = percent;
        const unit = "%";
        return includeUnits ? value + unit : value;
    }

    function formatVisibility(distance) {
        if (distance == null) {
            return null;
        }
        var value;
        var unit;
        if (SettingsData.useFahrenheit) {
            value = distance / 1609.344;
            unit = "mi";
            if (value < 1) {
                value = Math.round(value * 5280 / 50) * 50;
                unit = "ft";
                return value + " " + unit;
            }
            value = value.toFixed(1);
        } else {
            value = distance;
            unit = "m";
            if (value > 1000) {
                value = (value / 1000).toFixed(1);
                unit = "km";
            }
        }

        return value + " " + unit;
    }

    function formatTime(isoString) {
        if (!isoString)
            return "--";

        try {
            const date = new Date(isoString);
            const format = SettingsData.use24HourClock ? "HH:mm" : "h:mm AP";
            return date.toLocaleTimeString(Qt.locale(), format);
        } catch (e) {
            return "--";
        }
    }

    function calendarDayDifference(date1, date2) {
        const d1 = Date.UTC(date1.getFullYear(), date1.getMonth(), date1.getDate());
        const d2 = Date.UTC(date2.getFullYear(), date2.getMonth(), date2.getDate());
        return Math.floor((d2 - d1) / (1000 * 60 * 60 * 24));
    }

    function calendarHourDifference(date1, date2) {
        const d1 = Date.UTC(date1.getFullYear(), date1.getMonth(), date1.getDate(), date1.getHours());
        const d2 = Date.UTC(date2.getFullYear(), date2.getMonth(), date2.getDate(), date2.getHours());
        return Math.floor((d2 - d1) / (1000 * 60 * 60));
    }

    function formatForecastDay(isoString, index) {
        const date = isoString ? new Date(isoString.slice(0, 10) + "T12:00:00") : new Date();
        if (!isoString)
            date.setDate(date.getDate() + index);
        const locale = I18n.locale();
        return locale.dayName(date.getDay(), Locale.ShortFormat);
    }

    function getWeatherApiUrl() {
        if (!location) {
            return null;
        }
        return getWeatherApiUrlForCoords(location.latitude, location.longitude);
    }

    function getGeocodingUrl(query) {
        return "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(query) + "&count=1&language=en&format=json";
    }

    function getConfiguredLocationName() {
        return SettingsData.weatherLocation;
    }

    function setLocation(lat, lon, city, country) {
        root.location = {
            city: city || I18n.tr("Local Weather"),
            country: country || "",
            latitude: lat,
            longitude: lon
        };
    }

    function updateLocationCity(city, country) {
        if (!root.location)
            return;

        root.location = {
            latitude: root.location.latitude,
            longitude: root.location.longitude,
            city: city || root.location.city,
            country: country || root.location.country
        };

        if (root.weather.available) {
            root.weather = Object.assign({}, root.weather, {
                city: city || root.weather.city,
                country: country || root.weather.country
            });
        }
    }

    function getWeatherApiUrlForCoords(lat, lon) {
        if (lat == null || lon == null)
            return null;

        const params = ["latitude=" + lat, "longitude=" + lon, "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,surface_pressure,wind_speed_10m,wind_direction_10m", "daily=sunrise,sunset,moonrise,moonset,temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max", "hourly=temperature_2m,weather_code,precipitation_probability,wind_speed_10m,apparent_temperature,relative_humidity_2m,surface_pressure,visibility,cloud_cover,uv_index,dew_point_2m", "timezone=auto", "forecast_days=7"];

        return "https://api.open-meteo.com/v1/forecast?" + params.join('&');
    }

    function addRef() {
        refCount++;

        if (refCount === 1 && !weather.available && SettingsData.weatherEnabled) {
            fetchWeather();
        }
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }

    function updateLocation() {
        const useAuto = SettingsData.useAutoLocation;
        const coords = SettingsData.weatherCoordinates;
        const cityName = SettingsData.weatherLocation;

        if (useAuto) {
            getLocationFromService();
            return;
        }

        if (coords) {
            const parts = coords.split(",");
            if (parts.length === 2) {
                const lat = parseFloat(parts[0]);
                const lon = parseFloat(parts[1]);
                if (!isNaN(lat) && !isNaN(lon)) {
                    if (cityName) {
                        // User provided both: trust the configured name and coordinates, skip geocoding
                        setLocation(lat, lon, cityName, "");
                        fetchWeather(lat, lon);
                    } else {
                        getLocationFromCoords(lat, lon);
                    }
                    return;
                }
            }
        }

        if (cityName) {
            getLocationFromCity(cityName);
        } else {
            root.handleWeatherFailure();
        }
    }

    function getLocationFromCoords(lat, lon) {
        // Use coordinates immediately for weather; resolve city name in parallel with fallbacks
        setLocation(lat, lon, I18n.tr("Local Weather"), "");
        fetchWeather(lat, lon);
        resolveCityName(lat, lon);
    }

    function getLocationFromCity(city) {
        cityGeocodeFetcher.command = lowPriorityCmd.concat(fetchCmd, [getGeocodingUrl(city)]);
        cityGeocodeFetcher.running = true;
    }

    function getLocationFromService() {
        if (!LocationService.valid) {
            getLocationFromIP();
            return;
        }

        const lat = LocationService.latitude;
        const lon = LocationService.longitude;

        if (lat === 0 && lon === 0) {
            getLocationFromIP();
            return;
        }

        getLocationFromCoords(lat, lon);
    }

    function getLocationFromIP() {
        ipLocationFetcher.running = true;
    }

    function resolveCityName(lat, lon) {
        // Cancel any in-flight city resolution to avoid stale updates
        if (nominatimFetcher.running)
            nominatimFetcher.running = false;
        if (photonFetcher.running)
            photonFetcher.running = false;
        if (bigDataCloudFetcher.running)
            bigDataCloudFetcher.running = false;

        root._geocodeReqId++;
        root._pendingCoords = {
            latitude: lat,
            longitude: lon,
            reqId: root._geocodeReqId
        };

        tryNominatim(lat, lon, root._geocodeReqId);
    }

    function tryNominatim(lat, lon, reqId) {
        const url = "https://nominatim.openstreetmap.org/reverse?lat=" + lat + "&lon=" + lon + "&format=json&addressdetails=1&accept-language=en";
        nominatimFetcher.command = lowPriorityCmd.concat(fetchCmd, ["--user-agent", "Dux Shell Weather Widget", url]);
        nominatimFetcher.reqId = reqId;
        nominatimFetcher.running = true;
    }

    function tryPhoton(lat, lon, reqId) {
        const url = "https://photon.komoot.io/reverse?lat=" + lat + "&lon=" + lon + "&lang=en";
        photonFetcher.command = lowPriorityCmd.concat(fetchCmd, [url]);
        photonFetcher.reqId = reqId;
        photonFetcher.running = true;
    }

    function tryBigDataCloud(lat, lon, reqId) {
        const url = "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=" + lat + "&longitude=" + lon + "&localityLanguage=zh";
        bigDataCloudFetcher.command = lowPriorityCmd.concat(fetchCmd, [url]);
        bigDataCloudFetcher.reqId = reqId;
        bigDataCloudFetcher.running = true;
    }

    function fetchWeather(lat, lon) {
        if (root.refCount === 0 || !SettingsData.weatherEnabled) {
            return;
        }

        if (lat == null || lon == null) {
            if (!location) {
                updateLocation();
                return;
            }
            lat = location.latitude;
            lon = location.longitude;
        }

        if (weatherFetcher.running) {
            return;
        }

        const now = Date.now();
        if (now - root.lastFetchTime < root.minFetchInterval) {
            return;
        }

        const apiUrl = getWeatherApiUrlForCoords(lat, lon);
        if (!apiUrl) {
            return;
        }

        root.lastFetchTime = now;
        root.weather.loading = true;
        weatherFetcher.command = lowPriorityCmd.concat(root.fetchCmd, [apiUrl]);
        weatherFetcher.running = true;
    }

    function forceRefresh() {
        root.lastFetchTime = 0; // Reset throttle
        fetchWeather();
    }

    function nextInterval() {
        const jitter = Math.floor(Math.random() * 15000) - 7500;
        return Math.max(60000, root.updateInterval + jitter);
    }

    function handleWeatherSuccess() {
        root.retryAttempts = 0;
        root.persistentRetryCount = 0;
        if (persistentRetryTimer.running) {
            persistentRetryTimer.stop();
        }
        if (updateTimer.interval !== root.updateInterval) {
            updateTimer.interval = root.updateInterval;
        }
    }

    property string lastFetchError: ""

    function handleWeatherFailure(reason) {
        if (reason)
            root.lastFetchError = reason;
        root.retryAttempts++;
        if (root.retryAttempts < root.maxRetryAttempts) {
            retryTimer.start();
        } else {
            root.retryAttempts = 0;
            log.warn("Weather fetch failed:", root.lastFetchError || "no output from fetcher");
            if (!root.weather.available) {
                root.weather.loading = false;
            }
            const backoffDelay = Math.min(60000 * Math.pow(2, persistentRetryCount), 300000);
            persistentRetryCount++;
            persistentRetryTimer.interval = backoffDelay;
            persistentRetryTimer.start();
        }
    }

    Process {
        id: nominatimFetcher
        property int reqId: 0
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                if (nominatimFetcher.reqId !== root._geocodeReqId)
                    return;

                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.tryPhoton(root._pendingCoords.latitude, root._pendingCoords.longitude, root._geocodeReqId);
                    return;
                }

                try {
                    const data = JSON.parse(raw);
                    const address = data.address || {};
                    const city = address.hamlet || address.city || address.town || address.village || I18n.tr("Unknown");
                    const country = address.country || I18n.tr("Unknown");
                    root.updateLocationCity(city, country);
                } catch (e) {
                    root.tryPhoton(root._pendingCoords.latitude, root._pendingCoords.longitude, root._geocodeReqId);
                }
            }
        }

        onExited: exitCode => {
            if (nominatimFetcher.reqId !== root._geocodeReqId)
                return;
            if (exitCode !== 0) {
                root.tryPhoton(root._pendingCoords.latitude, root._pendingCoords.longitude, root._geocodeReqId);
            }
        }
    }

    Process {
        id: photonFetcher
        property int reqId: 0
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                if (photonFetcher.reqId !== root._geocodeReqId)
                    return;

                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.tryBigDataCloud(root._pendingCoords.latitude, root._pendingCoords.longitude, root._geocodeReqId);
                    return;
                }

                try {
                    const data = JSON.parse(raw);
                    const features = data.features;
                    if (!features || features.length === 0) {
                        throw new Error("No Photon results");
                    }

                    const props = features[0].properties || {};
                    const city = props.city || props.town || props.village || props.locality || props.name || I18n.tr("Unknown");
                    const country = props.country || I18n.tr("Unknown");
                    root.updateLocationCity(city, country);
                } catch (e) {
                    root.tryBigDataCloud(root._pendingCoords.latitude, root._pendingCoords.longitude, root._geocodeReqId);
                }
            }
        }

        onExited: exitCode => {
            if (photonFetcher.reqId !== root._geocodeReqId)
                return;
            if (exitCode !== 0) {
                root.tryBigDataCloud(root._pendingCoords.latitude, root._pendingCoords.longitude, root._geocodeReqId);
            }
        }
    }

    Process {
        id: bigDataCloudFetcher
        property int reqId: 0
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                if (bigDataCloudFetcher.reqId !== root._geocodeReqId)
                    return;

                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    // All city resolution fallbacks failed; weather is already displayed
                    return;
                }

                try {
                    const data = JSON.parse(raw);
                    const city = data.city || data.locality || I18n.tr("Unknown");
                    const country = data.countryName || I18n.tr("Unknown");
                    root.updateLocationCity(city, country);
                } catch (e) {
                    // All fallbacks failed; keep placeholder city name
                }
            }
        }

        onExited: exitCode => {
            if (bigDataCloudFetcher.reqId !== root._geocodeReqId)
                return;
        // Final fallback; no further action needed
        }
    }

    Process {
        id: ipLocationFetcher
        running: false
        command: lowPriorityCmd.concat(fetchCmd, ["http://ip-api.com/json/"])

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.handleWeatherFailure();
                    return;
                }

                try {
                    const data = JSON.parse(raw);

                    if (data.status === "fail") {
                        throw new Error("IP location lookup failed");
                    }

                    const lat = parseFloat(data.lat);
                    const lon = parseFloat(data.lon);
                    const city = data.city;

                    if (!city || isNaN(lat) || isNaN(lon)) {
                        throw new Error("Missing or invalid location data");
                    }

                    setLocation(lat, lon, city, data.country || "");
                    fetchWeather(lat, lon);
                } catch (e) {
                    root.handleWeatherFailure();
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.handleWeatherFailure();
            }
        }
    }

    Process {
        id: cityGeocodeFetcher
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.handleWeatherFailure();
                    return;
                }

                try {
                    const data = JSON.parse(raw);
                    const results = data.results;

                    if (!results || results.length === 0) {
                        throw new Error("No results found");
                    }

                    const result = results[0];

                    root.location = {
                        city: result.name,
                        country: result.country,
                        latitude: result.latitude,
                        longitude: result.longitude,
                        elevation: data.elevation
                    };

                    fetchWeather();
                } catch (e) {
                    root.handleWeatherFailure();
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.handleWeatherFailure();
            }
        }
    }

    Process {
        id: weatherFetcher
        running: false

        stderr: StdioCollector {
            id: weatherFetchErr
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw[0] !== "{") {
                    root.handleWeatherFailure(weatherFetchErr.text.trim());
                    return;
                }

                try {
                    const data = JSON.parse(raw);

                    if (!data.current || !data.daily || !data.hourly) {
                        throw new Error("Required weather data fields missing");
                    }

                    const hourly = data.hourly;
                    const hourly_forecast = [];
                    if (hourly.time && hourly.time.length > 0) {
                        for (let i = 0; i < hourly.time.length; i++) {
                            const tempMinC = hourly.temperature_2m_min?.[i] || 0;
                            const tempMaxC = hourly.temperature_2m_max?.[i] || 0;
                            const tempMinF = tempMinC * 9 / 5 + 32;
                            const tempMaxF = tempMaxC * 9 / 5 + 32;

                            const tempC = hourly.temperature_2m?.[i] || 0;
                            const tempF = tempC * 9 / 5 + 32;
                            const feelsLikeC = hourly.apparent_temperature?.[i] || tempC;
                            const feelsLikeF = feelsLikeC * 9 / 5 + 32;

                            const sunrise = new Date(data.daily.sunrise?.[Math.floor(i / 24)]);
                            const sunset = new Date(data.daily.sunset?.[Math.floor(i / 24)]);
                            const time = new Date(hourly.time[i]);
                            const isDay = sunrise < time && time < sunset;

                            hourly_forecast.push({
                                "time": formatTime(hourly.time[i]),
                                "rawTime": hourly.time[i],
                                "temp": Math.round(tempC),
                                "tempF": Math.round(tempF),
                                "feelsLike": Math.round(feelsLikeC),
                                "feelsLikeF": Math.round(feelsLikeF),
                                "wCode": hourly.weather_code?.[i] || 0,
                                "humidity": Math.round(hourly.relative_humidity_2m?.[i] || 0),
                                "wind": Math.round(hourly.wind_speed_10m?.[i] || 0),
                                "pressure": Math.round(hourly.surface_pressure?.[i] || 0),
                                "precipitationProbability": Math.round(hourly.precipitation_probability?.[i] || 0),
                                "visibility": Math.round(hourly.visibility?.[i] || 0),
                                "isDay": isDay
                            });
                        }
                    }

                    const daily = data.daily;
                    const forecast = [];
                    if (daily.time && daily.time.length > 0) {
                        for (let i = 0; i < daily.time.length; i++) {
                            const tempMinC = daily.temperature_2m_min?.[i] || 0;
                            const tempMaxC = daily.temperature_2m_max?.[i] || 0;
                            const tempMinF = (tempMinC * 9 / 5 + 32);
                            const tempMaxF = (tempMaxC * 9 / 5 + 32);

                            forecast.push({
                                "rawDate": daily.time[i],
                                "day": formatForecastDay(daily.time[i], i),
                                "wCode": daily.weather_code?.[i] || 0,
                                "tempMin": Math.round(tempMinC),
                                "tempMax": Math.round(tempMaxC),
                                "tempMinF": Math.round(tempMinF),
                                "tempMaxF": Math.round(tempMaxF),
                                "precipitationProbability": Math.round(daily.precipitation_probability_max?.[i] || 0),
                                "sunrise": daily.sunrise?.[i] ? formatTime(daily.sunrise[i]) : "",
                                "sunset": daily.sunset?.[i] ? formatTime(daily.sunset[i]) : "",
                                "rawSunrise": daily.sunrise?.[i] || "",
                                "rawSunset": daily.sunset?.[i] || ""
                            });
                        }
                    }

                    const current = data.current;
                    const currentUnits = data.current_units || {};

                    const tempC = current.temperature_2m || 0;
                    const tempF = tempC * 9 / 5 + 32;
                    const feelsLikeC = current.apparent_temperature || tempC;
                    const feelsLikeF = feelsLikeC * 9 / 5 + 32;

                    const currentHour = hourly.time?.findIndex(time => time.slice(0, 13) === current.time?.slice(0, 13)) ?? -1;
                    const hourlyValue = key => {
                        const value = hourly[key]?.[currentHour];
                        return Number.isFinite(value) ? value : null;
                    };
                    root.lastFetchError = "";
                    root.weather = {
                        "available": true,
                        "loading": false,
                        "temp": Math.round(tempC),
                        "tempF": Math.round(tempF),
                        "feelsLike": Math.round(feelsLikeC),
                        "feelsLikeF": Math.round(feelsLikeF),
                        "city": root.location?.city || I18n.tr("Unknown"),
                        "country": root.location?.country || I18n.tr("Unknown"),
                        "wCode": current.weather_code || 0,
                        "humidity": Math.round(current.relative_humidity_2m || 0),
                        "wind": Math.round(current.wind_speed_10m || 0),
                        "sunrise": formatTime(daily.sunrise?.[0]) || "06:00",
                        "sunset": formatTime(daily.sunset?.[0]) || "18:00",
                        "rawSunrise": daily.sunrise?.[0] || "",
                        "rawSunset": daily.sunset?.[0] || "",
                        "moonrise": daily.moonrise?.[0] ?? "",
                        "moonset": daily.moonset?.[0] ?? "",
                        "utcOffsetSeconds": data.utc_offset_seconds ?? null,
                        "currentHourIndex": currentHour >= 0 ? currentHour : null,
                        "uv": hourlyValue("uv_index"),
                        "visibility": hourlyValue("visibility"),
                        "dewPoint": hourlyValue("dew_point_2m"),
                        "windDirection": Number.isFinite(current.wind_direction_10m) ? current.wind_direction_10m : null,
                        "pressure": Math.round(current.surface_pressure || 0),
                        "precipitationProbability": Math.round(daily.precipitation_probability_max?.[0] || 0),
                        "isDay": Boolean(current.is_day),
                        "forecast": forecast,
                        "hourlyForecast": hourly_forecast
                    };
                    root.handleWeatherSuccess();
                } catch (e) {
                    root.handleWeatherFailure();
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.handleWeatherFailure();
            }
        }
    }

    Timer {
        id: updateTimer
        interval: nextInterval()
        running: root.refCount > 0 && SettingsData.weatherEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.fetchWeather();
            interval = nextInterval();
        }
    }

    Timer {
        id: retryTimer
        interval: root.retryDelay
        running: false
        repeat: false
        onTriggered: {
            root.fetchWeather();
        }
    }

    Timer {
        id: persistentRetryTimer
        interval: 60000
        running: false
        repeat: false
        onTriggered: {
            if (!root.weather.available) {
                root.weather.loading = true;
            }
            root.fetchWeather();
        }
    }

    Connections {
        target: LocationService
        enabled: root.refCount > 0 && SettingsData.weatherEnabled

        function onLocationChanged(data) {
            if (!SettingsData.useAutoLocation)
                return;
            if (data.latitude === 0 && data.longitude === 0) {
                root.getLocationFromIP();
                return;
            }
            root.getLocationFromCoords(data.latitude, data.longitude);
        }
    }

    Component.onCompleted: {
        SettingsData.weatherCoordinatesChanged.connect(() => {
            root.location = null;
            root.weather = emptyWeather();
            root.lastFetchTime = 0;
            root.forceRefresh();
        });

        SettingsData.weatherLocationChanged.connect(() => {
            root.location = null;
            root.lastFetchTime = 0;
            root.forceRefresh();
        });

        SettingsData.useAutoLocationChanged.connect(() => {
            root.location = null;
            root.weather = emptyWeather();
            root.lastFetchTime = 0;
            root.forceRefresh();
        });

        SettingsData.weatherEnabledChanged.connect(() => {
            if (SettingsData.weatherEnabled && root.refCount > 0 && !root.weather.available) {
                root.forceRefresh();
            } else if (!SettingsData.weatherEnabled) {
                updateTimer.stop();
                retryTimer.stop();
                persistentRetryTimer.stop();
                if (weatherFetcher.running) {
                    weatherFetcher.running = false;
                }
            }
        });
    }
}
