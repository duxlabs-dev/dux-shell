.pragma library

function toF(celsius) {
    return celsius * 9 / 5 + 32;
}

// data is an Open-Meteo forecast response. labels carries the formatters and
// location names, which depend on QML singletons.
function fromOpenMeteo(data, labels) {
    if (!data?.current || !data.daily || !data.hourly)
        throw new Error("Required weather data fields missing");

    const hourly = data.hourly;
    const daily = data.daily;
    const current = data.current;

    const hourlyForecast = [];
    for (let i = 0; i < (hourly.time?.length ?? 0); i++) {
        const tempC = hourly.temperature_2m?.[i] || 0;
        const feelsLikeC = hourly.apparent_temperature?.[i] || tempC;
        const sunrise = new Date(daily.sunrise?.[Math.floor(i / 24)]);
        const sunset = new Date(daily.sunset?.[Math.floor(i / 24)]);
        const time = new Date(hourly.time[i]);

        hourlyForecast.push({
            "time": labels.formatTime(hourly.time[i]),
            "rawTime": hourly.time[i],
            "temp": Math.round(tempC),
            "tempF": Math.round(toF(tempC)),
            "feelsLike": Math.round(feelsLikeC),
            "feelsLikeF": Math.round(toF(feelsLikeC)),
            "wCode": hourly.weather_code?.[i] || 0,
            "humidity": Math.round(hourly.relative_humidity_2m?.[i] || 0),
            "wind": Math.round(hourly.wind_speed_10m?.[i] || 0),
            "pressure": Math.round(hourly.surface_pressure?.[i] || 0),
            "precipitationProbability": Math.round(hourly.precipitation_probability?.[i] || 0),
            "visibility": Math.round(hourly.visibility?.[i] || 0),
            "isDay": sunrise < time && time < sunset
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
            "precipitationProbability": Math.round(daily.precipitation_probability_max?.[i] || 0),
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
        "humidity": Math.round(current.relative_humidity_2m || 0),
        "wind": Math.round(current.wind_speed_10m || 0),
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
        "pressure": Math.round(current.surface_pressure || 0),
        "precipitationProbability": Math.round(daily.precipitation_probability_max?.[0] || 0),
        "isDay": Boolean(current.is_day),
        "forecast": forecast,
        "hourlyForecast": hourlyForecast
    };
}
