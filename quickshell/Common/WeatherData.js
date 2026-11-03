.pragma library

function toF(celsius) {
    return celsius * 9 / 5 + 32;
}

// Readings beyond temperature are optional per provider; missing ones stay null so the UI shows a placeholder.
function roundOrNull(value) {
    return Number.isFinite(value) ? Math.round(value) : null;
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
    const hourlyValue = key => {
        const value = hourly[key]?.[currentHour];
        return Number.isFinite(value) ? value : null;
    };

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
        "currentHourIndex": currentHour >= 0 ? currentHour : null,
        "uv": hourlyValue("uv_index"),
        "visibility": hourlyValue("visibility"),
        "dewPoint": hourlyValue("dew_point_2m"),
        "windDirection": Number.isFinite(current.wind_direction_10m) ? current.wind_direction_10m : null,
        "pressure": roundOrNull(current.surface_pressure),
        "precipitationProbability": roundOrNull(daily.precipitation_probability_max?.[0]),
        "isDay": Boolean(current.is_day),
        "forecast": forecast,
        "hourlyForecast": hourlyForecast
    };
}
