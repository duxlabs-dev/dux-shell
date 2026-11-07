.pragma library

function toF(celsius) {
    return celsius * 9 / 5 + 32;
}

// Readings beyond temperature are optional per provider; missing ones stay null so the UI shows a placeholder.
function roundOrNull(value) {
    return Number.isFinite(value) ? Math.round(value) : null;
}

function finiteOrNull(value) {
    return Number.isFinite(value) ? value : null;
}

// Upper bounds of each category but the last, which is open-ended.
var airQualityBounds = {
    "european": [20, 40, 60, 80, 100],
    "us": [50, 100, 150, 200, 300],
    // The WHO's 2021 guideline for the 24-hour mean PM2.5 in µg/m³, then its interim targets 4 to 1.
    "who": [15, 25, 37.5, 50, 75]
};

// The WHO guideline for the 24-hour mean PM2.5, µg/m³.
var whoGuideline = 15;

// How many times the guideline a reading above it is, rounded up to 0.1: 15.2 reads as
// 1.1×, never as 1.0× next to a marker that says it is above.
function timesGuideline(mean) {
    return Math.ceil(mean / whoGuideline * 10 - 1e-9) / 10;
}

// Europe as boxes of [south, north, west, east] degrees, rough on purpose: the European
// index for places in Europe, Iceland and the Atlantic islands included, the US index
// for everywhere else. The southern edges run between Europe and North Africa, the
// eastern ones leave out the Middle East.
var europeBoxes = [
    [27.5, 29.5, -18.5, -13.3], // Canary Islands
    [32.3, 33.2, -17.4, -16.2], // Madeira
    [36.8, 40.0, -31.5, -24.8], // Azores
    [36.0, 82.0, -25.0, -5.5], // Iceland, the British Isles, the Iberian west coast
    [36.0, 82.0, -5.5, -1.0], // Spain down to Gibraltar, above Morocco
    [38.0, 82.0, -1.0, 8.0], // France, the Balearics, Sardinia, above Algeria
    [37.5, 82.0, 8.0, 11.5], // Italy's west, above Tunisia
    [34.7, 82.0, 11.5, 30.0], // Sicily, Malta, the Balkans, Greece and Crete, Svalbard
    [34.5, 82.0, 30.0, 35.5], // Cyprus, western Turkey
    [37.5, 82.0, 35.5, 44.0], // eastern Turkey, above Syria and Iraq
    [41.0, 82.0, 44.0, 60.0] // European Russia up to the Urals
];

function inEurope(latitude, longitude) {
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude))
        return false;
    return europeBoxes.some(([south, north, west, east]) => latitude >= south && latitude <= north && longitude >= west && longitude <= east);
}

// option is the tile's "auto", "european", "us" or "who". Auto goes by the weather
// location: the European index in Europe, the US one everywhere else.
function airQualityScale(option, latitude, longitude) {
    if (Object.prototype.hasOwnProperty.call(airQualityBounds, option))
        return option;
    return inEurope(latitude, longitude) ? "european" : "us";
}

// The reading a scale is for: an index, or for the WHO the 24-hour mean PM2.5.
function airQualityIndex(weather, scale) {
    switch (scale) {
    case "european":
        return finiteOrNull(weather?.europeanAqi);
    case "who":
        return finiteOrNull(weather?.pm25Mean24h);
    }
    return finiteOrNull(weather?.usAqi);
}

// Index of the category within the scale, -1 without a reading.
function airQualityCategory(scale, index) {
    if (!Number.isFinite(index))
        return -1;
    const bounds = airQualityBounds[scale] ?? airQualityBounds.us;
    const category = bounds.findIndex(bound => index <= bound);
    return category < 0 ? bounds.length : category;
}

// The air quality tile lives only in a saved weather dash layout; the default layout leaves it out.
function wantsAirQuality(dashOptions) {
    const widgets = dashOptions?.weather?.widgets;
    return Array.isArray(widgets) && widgets.some(widget => widget?.id === "airQuality");
}

// data is an Open-Meteo forecast response. labels carries the formatters and
// location names, which depend on QML singletons.
function fromOpenMeteo(data, labels) {
    if (!data?.current || !data.daily || !data.hourly)
        throw new Error("Required weather data fields missing");

    const hourly = data.hourly;
    const daily = data.daily;
    const current = data.current;

    // Days with a DST change have 23 or 25 hours, so match hours to days by date.
    const dayIndex = {};
    (daily.time ?? []).forEach((day, i) => dayIndex[day] = i);

    const hourlyForecast = [];
    for (let i = 0; i < (hourly.time?.length ?? 0); i++) {
        const tempC = hourly.temperature_2m?.[i] || 0;
        const feelsLikeC = hourly.apparent_temperature?.[i] || tempC;
        const day = dayIndex[hourly.time[i].slice(0, 10)];
        const sunrise = new Date(daily.sunrise?.[day]);
        const sunset = new Date(daily.sunset?.[day]);
        const time = new Date(hourly.time[i]);

        hourlyForecast.push({
            "time": labels.formatTime(hourly.time[i]),
            "rawTime": hourly.time[i],
            "temp": Math.round(tempC),
            "tempF": Math.round(toF(tempC)),
            "feelsLike": Math.round(feelsLikeC),
            "feelsLikeF": Math.round(toF(feelsLikeC)),
            "wCode": hourly.weather_code?.[i] || 0,
            "humidity": roundOrNull(hourly.relative_humidity_2m?.[i]),
            "wind": roundOrNull(hourly.wind_speed_10m?.[i]),
            "pressure": roundOrNull(hourly.surface_pressure?.[i]),
            "precipitationProbability": roundOrNull(hourly.precipitation_probability?.[i]),
            "visibility": roundOrNull(hourly.visibility?.[i]),
            "isDay": hourly.is_day?.[i] != null ? Boolean(hourly.is_day[i]) : sunrise <= time && time < sunset
        });
    }

    const forecast = [];
    for (let i = 0; i < (daily.time?.length ?? 0); i++) {
        const tempMinC = daily.temperature_2m_min?.[i] || 0;
        const tempMaxC = daily.temperature_2m_max?.[i] || 0;

        forecast.push({
            "rawDate": daily.time[i],
            "day": labels.formatDay(daily.time[i], i),
            "wCode": daily.weather_code?.[i] || 0,
            "tempMin": Math.round(tempMinC),
            "tempMax": Math.round(tempMaxC),
            "tempMinF": Math.round(toF(tempMinC)),
            "tempMaxF": Math.round(toF(tempMaxC)),
            "precipitationProbability": roundOrNull(daily.precipitation_probability_max?.[i]),
            "sunrise": daily.sunrise?.[i] ? labels.formatTime(daily.sunrise[i]) : "",
            "sunset": daily.sunset?.[i] ? labels.formatTime(daily.sunset[i]) : "",
            "rawSunrise": daily.sunrise?.[i] || "",
            "rawSunset": daily.sunset?.[i] || ""
        });
    }

    const tempC = current.temperature_2m || 0;
    const feelsLikeC = current.apparent_temperature || tempC;
    const currentHour = hourly.time?.findIndex(time => time.slice(0, 13) === current.time?.slice(0, 13)) ?? -1;
    const hourlyValue = key => finiteOrNull(hourly[key]?.[currentHour]);

    return {
        "available": true,
        "loading": false,
        "temp": Math.round(tempC),
        "tempF": Math.round(toF(tempC)),
        "feelsLike": Math.round(feelsLikeC),
        "feelsLikeF": Math.round(toF(feelsLikeC)),
        "city": labels.city,
        "country": labels.country,
        "wCode": current.weather_code || 0,
        "humidity": roundOrNull(current.relative_humidity_2m),
        "wind": roundOrNull(current.wind_speed_10m),
        "sunrise": labels.formatTime(daily.sunrise?.[0]) || "06:00",
        "sunset": labels.formatTime(daily.sunset?.[0]) || "18:00",
        "rawSunrise": daily.sunrise?.[0] || "",
        "rawSunset": daily.sunset?.[0] || "",
        "moonrise": daily.moonrise?.[0] ?? "",
        "moonset": daily.moonset?.[0] ?? "",
        "utcOffsetSeconds": data.utc_offset_seconds ?? null,
        "latitude": Number.isFinite(labels.latitude) ? labels.latitude : null,
        "longitude": Number.isFinite(labels.longitude) ? labels.longitude : null,
        "currentHourIndex": currentHour >= 0 ? currentHour : null,
        "uv": hourlyValue("uv_index"),
        "visibility": hourlyValue("visibility"),
        "dewPoint": hourlyValue("dew_point_2m"),
        "windDirection": Number.isFinite(current.wind_direction_10m) ? current.wind_direction_10m : null,
        "pressure": roundOrNull(current.surface_pressure),
        "precipitationProbability": roundOrNull(daily.precipitation_probability_max?.[0]),
        "europeanAqi": roundOrNull(current.european_aqi),
        "usAqi": roundOrNull(current.us_aqi),
        "pm25": finiteOrNull(current.pm2_5),
        "pm10": finiteOrNull(current.pm10),
        "pm25Mean24h": finiteOrNull(current.pm2_5_mean_24h),
        "isDay": Boolean(current.is_day),
        "forecast": forecast,
        "hourlyForecast": hourlyForecast
    };
}
