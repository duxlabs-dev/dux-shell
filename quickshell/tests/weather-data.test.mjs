import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const weatherData = loadScript(new URL("../Common/WeatherData.js", import.meta.url));

const labels = {
    formatTime: iso => iso ? iso.slice(11, 16) : "--",
    formatDay: iso => iso,
    city: "Bern",
    country: "Switzerland"
};

function hours(day, count) {
    return Array.from({ length: count }, (_, h) => `${day}T${String(h).padStart(2, "0")}:00`);
}

function openMeteo() {
    return {
        utc_offset_seconds: 3600,
        current: { time: "2026-11-02T14:15", temperature_2m: 7.6, apparent_temperature: 5.2, relative_humidity_2m: 81, is_day: 1, weather_code: 3, surface_pressure: 961.4, wind_speed_10m: 10.4, wind_direction_10m: 40 },
        hourly: {
            time: hours("2026-11-02", 24).concat(hours("2026-11-03", 24)),
            temperature_2m: Array(48).fill(6),
            uv_index: Array(48).fill(null).fill(1.5, 14, 15)
        },
        daily: {
            time: ["2026-11-02", "2026-11-03"],
            sunrise: ["2026-11-02T07:10", "2026-11-03T07:12"],
            sunset: ["2026-11-02T17:07", "2026-11-03T17:05"],
            temperature_2m_max: [8.4, 9.6],
            temperature_2m_min: [3.6, 2.4],
            weather_code: [3, 61],
            precipitation_probability_max: [5, 70]
        }
    };
}

test("fromOpenMeteo rejects a response without current, hourly or daily data", () => {
    for (const key of ["current", "hourly", "daily"]) {
        const data = openMeteo();
        delete data[key];
        assert.throws(() => weatherData.fromOpenMeteo(data, labels));
    }
});

test("fromOpenMeteo reads the current hour's hourly-only values", () => {
    const weather = weatherData.fromOpenMeteo(openMeteo(), labels);
    assert.equal(weather.currentHourIndex, 14);
    assert.equal(weather.uv, 1.5);
    assert.equal(weather.dewPoint, null);
    assert.equal(weather.temp, 8);
    assert.equal(weather.tempF, 46);
});

test("fromOpenMeteo marks each hour as day or night by that day's sun times", () => {
    const hourly = weatherData.fromOpenMeteo(openMeteo(), labels).hourlyForecast;
    assert.deepEqual([6, 8, 17, 18, 31, 32].map(i => hourly[i].isDay), [false, true, true, false, false, true]);
});

test("fromOpenMeteo converts the daily range to both units", () => {
    const day = weatherData.fromOpenMeteo(openMeteo(), labels).forecast[1];
    assert.deepEqual([day.tempMin, day.tempMax, day.tempMinF, day.tempMaxF, day.wCode], [2, 10, 36, 49, 61]);
});

test("fromOpenMeteo reads the current air quality and keeps missing readings null", () => {
    const data = openMeteo();
    Object.assign(data.current, { european_aqi: 32.6, us_aqi: 41, pm2_5: 10.8, pm2_5_mean_24h: 14.7 });
    const weather = weatherData.fromOpenMeteo(data, Object.assign({}, labels, { latitude: 46.95, longitude: 7.45 }));
    assert.deepEqual([weather.europeanAqi, weather.usAqi, weather.pm25, weather.pm10, weather.pm25Mean24h, weather.latitude, weather.longitude], [33, 41, 10.8, null, 14.7, 46.95, 7.45]);
    assert.deepEqual([weatherData.fromOpenMeteo(data, labels).latitude, weatherData.fromOpenMeteo(data, labels).longitude], [null, null]);
});

test("airQualityScale follows the option, else the weather location", () => {
    assert.equal(weatherData.airQualityScale("us", 46.95, 7.45), "us");
    assert.equal(weatherData.airQualityScale("european", 40.71, -74.01), "european");
    assert.equal(weatherData.airQualityScale("who", 46.95, 7.45), "who");
    assert.equal(weatherData.airQualityScale("who", 40.71, -74.01), "who");
    // Every option the tile offers is a scale of its own, none falls back to auto.
    for (const scale of Object.keys(weatherData.airQualityBounds))
        assert.equal(weatherData.airQualityScale(scale, -33.87, 151.21), scale);
    assert.equal(weatherData.airQualityScale("auto", 46.95, 7.45), "european");
    assert.equal(weatherData.airQualityScale("auto", 40.71, -74.01), "us");
    assert.equal(weatherData.airQualityScale("auto", null, null), "us");
});

// Places on both sides of the edges, where a box too wide or too narrow would show.
test("airQualityScale knows Europe from its neighbours", () => {
    const european = {
        "Reykjavík": [64.15, -21.94], "Las Palmas": [28.12, -15.43], "Funchal": [32.65, -16.91], "Ponta Delgada": [37.74, -25.67],
        "Lisbon": [38.72, -9.14], "Gibraltar": [36.14, -5.35], "Málaga": [36.72, -4.42], "Palma": [39.57, 2.65],
        "Cagliari": [39.22, 9.12], "Palermo": [38.12, 13.36], "Valletta": [35.9, 14.51], "Heraklion": [35.34, 25.13],
        "Nicosia": [35.17, 33.36], "Istanbul": [41.01, 28.98], "Erzurum": [39.9, 41.27], "Tbilisi": [41.72, 44.79],
        "Moscow": [55.76, 37.62], "Tromsø": [69.65, 18.96], "Longyearbyen": [78.22, 15.65]
    };
    const elsewhere = {
        "Tangier": [35.77, -5.8], "Tétouan": [35.57, -5.37], "Laayoune": [27.15, -13.2], "Algiers": [36.75, 3.06], "Tunis": [36.81, 10.18],
        "Bizerte": [37.27, 9.87], "Tripoli": [32.89, 13.19], "Cairo": [30.04, 31.24], "Beirut": [33.89, 35.5],
        "Aleppo": [36.2, 37.15], "Mosul": [36.34, 43.13], "Tehran": [35.69, 51.39], "New York": [40.71, -74.01],
        "Tokyo": [35.68, 139.69], "Delhi": [28.61, 77.21], "Sydney": [-33.87, 151.21], "Nairobi": [-1.29, 36.82],
        "McMurdo Station": [-77.85, 166.67], "Amundsen-Scott": [-90, 0]
    };
    for (const [place, [lat, lon]] of Object.entries(european))
        assert.equal(weatherData.airQualityScale("auto", lat, lon), "european", place);
    for (const [place, [lat, lon]] of Object.entries(elsewhere))
        assert.equal(weatherData.airQualityScale("auto", lat, lon), "us", place);
});

test("airQualityIndex picks the reading of the scale", () => {
    const weather = { europeanAqi: 33, usAqi: 41 };
    assert.equal(weatherData.airQualityIndex(weather, "european"), 33);
    assert.equal(weatherData.airQualityIndex(weather, "us"), 41);
    assert.equal(weatherData.airQualityIndex({ europeanAqi: 0 }, "european"), 0);
    assert.equal(weatherData.airQualityIndex({ europeanAqi: 33 }, "us"), null);
    // The WHO guideline is for the 24-hour mean, not the current PM2.5.
    assert.equal(weatherData.airQualityIndex({ pm25: 30, pm25Mean24h: 14.7 }, "who"), 14.7);
    assert.equal(weatherData.airQualityIndex({ pm25: 30 }, "who"), null);
});

test("airQualityCategory places each scale's boundaries in the lower category", () => {
    const european = [0, 20, 21, 40, 41, 60, 61, 80, 81, 100, 101, 250].map(i => weatherData.airQualityCategory("european", i));
    assert.deepEqual(european, [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
    const us = [0, 50, 51, 100, 101, 150, 151, 200, 201, 300, 301, 500].map(i => weatherData.airQualityCategory("us", i));
    assert.deepEqual(us, [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
    const who = [0, 15, 15.1, 25, 25.1, 37.5, 37.6, 50, 50.1, 75, 75.1, 300].map(i => weatherData.airQualityCategory("who", i));
    assert.deepEqual(who, [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
    assert.equal(weatherData.airQualityCategory("european", null), -1);
});

test("timesGuideline rounds up, so a reading above the guideline never reads 1.0×", () => {
    assert.deepEqual([15.1, 15.74, 16.5, 30, 45.2, 1000].map(weatherData.timesGuideline), [1.1, 1.1, 1.1, 2, 3.1, 66.7]);
});

test("wantsAirQuality is only true when the weather dash layout holds the tile", () => {
    assert.equal(weatherData.wantsAirQuality(undefined), false);
    assert.equal(weatherData.wantsAirQuality({ weather: { forecast: "cards" } }), false);
    assert.equal(weatherData.wantsAirQuality({ weather: { widgets: [{ id: "uv" }] } }), false);
    assert.equal(weatherData.wantsAirQuality({ overview: { widgets: [{ id: "airQuality" }] } }), false);
    assert.equal(weatherData.wantsAirQuality({ weather: { widgets: [null, { id: "airQuality", w: 1, h: 2 }] } }), true);
});
