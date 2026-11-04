.pragma library
.import "suncalc.js" as SunCalc

// Every provider answers with the Open-Meteo response shape, so WeatherData
// parses them all the same way.

const HOUR_MS = 3600000;
const USER_AGENT = "Dux Modular Shell Weather Widget (+https://github.com/duxlabs-dev/dux-shell)";

const catalog = [
    {
        id: "openmeteo",
        text: "Open-Meteo"
    },
    {
        id: "metno",
        text: "MET Norway"
    }
];

function pad(value) {
    return String(value).padStart(2, "0");
}

// Open-Meteo gives wall-clock times in the location's zone. MET Norway has no
// zone information, so its times use the machine's zone instead.
function localIso(ms) {
    const d = new Date(ms);
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + "T" + pad(d.getHours()) + ":" + pad(d.getMinutes());
}

function localMidnight(ms) {
    const d = new Date(ms);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
}

function utcOffsetSeconds() {
    return -new Date().getTimezoneOffset() * 60;
}

function finiteOr(value, fallback) {
    return Number.isFinite(value) ? value : fallback;
}

function maxOf(values) {
    const finite = values.filter(Number.isFinite);
    return finite.length ? Math.max(...finite) : null;
}

function minOf(values) {
    const finite = values.filter(Number.isFinite);
    return finite.length ? Math.min(...finite) : null;
}

function sunTimes(dayMs, lat, lon) {
    const noon = new Date(dayMs + 12 * HOUR_MS);
    const times = SunCalc.getTimes(noon, lat, lon);
    const valid = date => Number.isFinite(date?.getTime?.());
    // Polar day and night have no sunrise or sunset. Like Open-Meteo, polar
    // night gets both at midnight and polar day runs from midnight to
    // midnight, so day/night checks keep working.
    const polarDay = sunUp(times.solarNoon.getTime(), lat, lon) === 1;
    const nextMidnight = localMidnight(dayMs + 36 * HOUR_MS);
    return {
        sunrise: localIso(valid(times.sunrise) ? times.sunrise.getTime() : dayMs),
        sunset: localIso(valid(times.sunset) ? times.sunset.getTime() : polarDay ? nextMidnight : dayMs)
    };
}

// Day while the sun is above -0.833°, the same horizon as SunCalc's sunrise and sunset.
function sunUp(ms, lat, lon) {
    return SunCalc.getPosition(new Date(ms), lat, lon).altitude > -0.833 * Math.PI / 180 ? 1 : 0;
}

function openMeteoUrl(lat, lon) {
    const params = ["latitude=" + lat, "longitude=" + lon, "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,surface_pressure,wind_speed_10m,wind_direction_10m", "daily=sunrise,sunset,moonrise,moonset,temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max", "hourly=temperature_2m,weather_code,precipitation_probability,wind_speed_10m,apparent_temperature,relative_humidity_2m,surface_pressure,visibility,cloud_cover,uv_index,dew_point_2m", "timezone=auto", "forecast_days=7"];
    return "https://api.open-meteo.com/v1/forecast?" + params.join("&");
}

// MET Norway symbol codes, without the _day/_night/_polartwilight suffix.
const metnoCodes = {
    "clearsky": 0,
    "fair": 1,
    "partlycloudy": 2,
    "cloudy": 3,
    "fog": 45,
    "lightrainshowers": 80,
    "rainshowers": 81,
    "heavyrainshowers": 82,
    "lightrain": 61,
    "rain": 63,
    "heavyrain": 65,
    "lightsleetshowers": 80,
    "sleetshowers": 80,
    "heavysleetshowers": 82,
    "lightsleet": 66,
    "sleet": 66,
    "heavysleet": 67,
    "lightsnowshowers": 85,
    "snowshowers": 85,
    "heavysnowshowers": 86,
    "lightsnow": 71,
    "snow": 73,
    "heavysnow": 75
};

function metnoCode(symbol) {
    if (!symbol)
        return null;
    const name = symbol.split("_")[0];
    if (name.includes("thunder"))
        return 95;
    return metnoCodes[name] ?? null;
}

function metnoSymbol(entry, ...periods) {
    for (const period of periods) {
        const symbol = entry.data?.[period]?.summary?.symbol_code;
        if (symbol)
            return symbol;
    }
    return null;
}

function fromMetno(json, lat, lon, now) {
    const series = (json?.properties?.timeseries ?? []).map(entry => ({
                ms: Date.parse(entry.time),
                entry: entry,
                details: entry.data?.instant?.details ?? {}
            })).filter(item => Number.isFinite(item.ms));
    if (!series.length)
        throw new Error("MET Norway returned no timeseries");

    // Hourly steps run out after about two days, then become 6-hourly.
    const hourlySteps = [series[0]];
    for (let i = 1; i < series.length && series[i].ms - series[i - 1].ms === HOUR_MS; i++)
        hourlySteps.push(series[i]);

    // MET Norway's pressure is at sea level and its UV index assumes a clear
    // sky, unlike Open-Meteo's surface pressure and UV index, so both are left out.
    // Hourly indexes are hours since local midnight; the forecast starts at the
    // current hour, so the hours before it repeat the first step.
    const midnight = localMidnight(series[0].ms);
    const hourly = {
        time: [],
        temperature_2m: [],
        apparent_temperature: [],
        relative_humidity_2m: [],
        dew_point_2m: [],
        cloud_cover: [],
        wind_speed_10m: [],
        weather_code: [],
        precipitation_probability: [],
        // Per hour, so day and night stay right when the machine's time zone
        // is far from the location's and its days split the location's nights.
        is_day: []
    };
    for (let ms = midnight; ms <= hourlySteps[hourlySteps.length - 1].ms; ms += HOUR_MS) {
        const step = hourlySteps.find(item => item.ms === ms) ?? hourlySteps[0];
        const d = step.details;
        hourly.time.push(localIso(ms));
        hourly.temperature_2m.push(finiteOr(d.air_temperature, null));
        hourly.apparent_temperature.push(finiteOr(d.apparent_air_temperature, null));
        hourly.relative_humidity_2m.push(finiteOr(d.relative_humidity, null));
        hourly.dew_point_2m.push(finiteOr(d.dew_point_temperature, null));
        hourly.cloud_cover.push(finiteOr(d.cloud_area_fraction, null));
        hourly.wind_speed_10m.push(Number.isFinite(d.wind_speed) ? d.wind_speed * 3.6 : null);
        hourly.weather_code.push(metnoCode(metnoSymbol(step.entry, "next_1_hours", "next_6_hours")));
        hourly.precipitation_probability.push(finiteOr(step.entry.data?.next_1_hours?.details?.probability_of_precipitation, null));
        hourly.is_day.push(sunUp(ms, lat, lon));
    }

    const daily = {
        time: [],
        sunrise: [],
        sunset: [],
        temperature_2m_max: [],
        temperature_2m_min: [],
        weather_code: [],
        precipitation_probability_max: []
    };
    for (let day = midnight; day <= series[series.length - 1].ms; day = localMidnight(day + 36 * HOUR_MS)) {
        const steps = series.filter(item => item.ms >= day && item.ms < localMidnight(day + 36 * HOUR_MS));
        if (!steps.length)
            break;
        const sixHourly = steps.map(item => item.entry.data?.next_6_hours?.details ?? {});
        // The 06:00 step's 12-hour symbol is MET Norway's daytime summary. A
        // trailing day with only its midnight step would show a night forecast.
        const summary = steps.find(item => new Date(item.ms).getHours() >= 6) ?? (day === midnight ? steps[0] : null);
        if (!summary)
            break;
        const sun = sunTimes(day, lat, lon);
        daily.time.push(localIso(day).slice(0, 10));
        daily.sunrise.push(sun.sunrise);
        daily.sunset.push(sun.sunset);
        daily.temperature_2m_max.push(maxOf(steps.map(item => item.details.air_temperature).concat(sixHourly.map(d => d.air_temperature_max))));
        daily.temperature_2m_min.push(minOf(steps.map(item => item.details.air_temperature).concat(sixHourly.map(d => d.air_temperature_min))));
        daily.weather_code.push(metnoCode(metnoSymbol(summary.entry, "next_12_hours", "next_6_hours", "next_1_hours")));
        // After about two days MET Norway only has 6-hourly steps.
        daily.precipitation_probability_max.push(maxOf(steps.map(item => item.entry.data?.next_1_hours?.details?.probability_of_precipitation ?? item.entry.data?.next_6_hours?.details?.probability_of_precipitation)));
    }

    const first = series.find(item => item.ms <= now && now < item.ms + HOUR_MS) ?? series[0];
    return {
        utc_offset_seconds: utcOffsetSeconds(),
        current: {
            time: localIso(first.ms),
            temperature_2m: finiteOr(first.details.air_temperature, null),
            apparent_temperature: finiteOr(first.details.apparent_air_temperature, null),
            relative_humidity_2m: finiteOr(first.details.relative_humidity, null),
            wind_speed_10m: Number.isFinite(first.details.wind_speed) ? first.details.wind_speed * 3.6 : null,
            wind_direction_10m: finiteOr(first.details.wind_from_direction, null),
            weather_code: metnoCode(metnoSymbol(first.entry, "next_1_hours", "next_6_hours")),
            is_day: sunUp(now, lat, lon)
        },
        hourly: hourly,
        daily: daily
    };
}

function request(id, lat, lon) {
    switch (id) {
    case "openmeteo":
        return {
            url: openMeteoUrl(lat, lon)
        };
    case "metno":
        // MET Norway rejects more than four decimals and anonymous clients.
        return {
            url: "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=" + Number(lat).toFixed(4) + "&lon=" + Number(lon).toFixed(4),
            userAgent: USER_AGENT
        };
    }
    throw new Error("Unknown weather provider " + id);
}

function parse(id, raw, lat, lon, now) {
    const json = JSON.parse(raw);
    switch (id) {
    case "openmeteo":
        return json;
    case "metno":
        return fromMetno(json, lat, lon, now);
    }
    throw new Error("Unknown weather provider " + id);
}
