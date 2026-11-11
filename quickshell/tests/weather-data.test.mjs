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
