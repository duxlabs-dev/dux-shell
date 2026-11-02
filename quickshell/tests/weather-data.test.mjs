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

test("fillMissing takes only readings the primary provider lacks, matched by hour and day", () => {
    const primary = weatherData.fromOpenMeteo(openMeteo(), labels);
    primary.humidity = null;
    primary.uv = null;
    primary.hourlyForecast[14].humidity = null;
    primary.forecast[1].precipitationProbability = null;
    const extraData = openMeteo();
    extraData.current.relative_humidity_2m = 60;
    extraData.current.temperature_2m = 1;
    extraData.hourly.relative_humidity_2m = Array(48).fill(55);
    extraData.daily.precipitation_probability_max = [10, 90];
    const extra = weatherData.fromOpenMeteo(extraData, labels);
    extra.uv = 3;

    const filled = weatherData.fillMissing(primary, extra);
    assert.deepEqual([filled.humidity, filled.uv, filled.temp, filled.pressure], [60, 3, 8, 961]);
    assert.equal(filled.hourlyForecast[14].humidity, 55);
    assert.deepEqual([filled.forecast[0].precipitationProbability, filled.forecast[1].precipitationProbability], [5, 90]);
    assert.equal(weatherData.hasMissingReadings(primary), true);
});

test("fillMissing matches hours by instant when the providers report different time zones", () => {
    // Primary in machine time 12 hours ahead (like MET Norway), extra in the location's time.
    const primaryData = openMeteo();
    primaryData.utc_offset_seconds = 13 * 3600;
    primaryData.hourly.time = primaryData.hourly.time.map(time => {
        const ms = Date.parse(time + "Z") + 12 * 3600000;
        return new Date(ms).toISOString().slice(0, 16);
    });
    const primary = weatherData.fromOpenMeteo(primaryData, labels);
    primary.hourlyForecast[10].humidity = null;
    const extraData = openMeteo();
    extraData.hourly.relative_humidity_2m = extraData.hourly.time.map((time, i) => i);
    const extra = weatherData.fromOpenMeteo(extraData, labels);

    const filled = weatherData.fillMissing(primary, extra);
    assert.equal(filled.hourlyForecast[10].humidity, 10);
});

test("fillMissing falls back to matching local times when a provider gives no offset", () => {
    const primary = weatherData.fromOpenMeteo(openMeteo(), labels);
    primary.hourlyForecast[10].humidity = null;
    const extraData = openMeteo();
    delete extraData.utc_offset_seconds;
    extraData.hourly.relative_humidity_2m = extraData.hourly.time.map((time, i) => i);
    const filled = weatherData.fillMissing(primary, weatherData.fromOpenMeteo(extraData, labels));
    assert.equal(filled.hourlyForecast[10].humidity, 10);
});

test("a missing apparent temperature stays null in both units instead of copying the air temperature", () => {
    const data = openMeteo();
    data.current.apparent_temperature = null;
    data.hourly.apparent_temperature = Array(48).fill(null);
    const weather = weatherData.fromOpenMeteo(data, labels);
    assert.deepEqual([weather.feelsLike, weather.feelsLikeF, weather.hourlyForecast[3].feelsLikeF], [null, null, null]);
});
