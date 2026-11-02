import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

process.env.TZ = "Europe/Zurich";

const providers = loadScript(new URL("../Common/WeatherProviders.js", import.meta.url));
const weatherData = loadScript(new URL("../Common/WeatherData.js", import.meta.url));

const HOUR_MS = 3600000;
const labels = { formatTime: iso => iso ?? "--", formatDay: iso => iso, city: "", country: "" };

function step(ms, temp, extra = {}) {
    return {
        time: new Date(ms).toISOString().replace(".000", ""),
        data: {
            instant: { details: { air_temperature: temp, relative_humidity: 70, wind_speed: 5, wind_from_direction: 60 } },
            next_1_hours: extra.next1 ?? { summary: { symbol_code: "cloudy" }, details: {} },
            next_6_hours: extra.next6 ?? { summary: { symbol_code: "cloudy" }, details: {} },
            next_12_hours: extra.next12 ?? { summary: { symbol_code: "cloudy" }, details: {} }
        }
    };
}

// 15:00 local on 2 Nov, hourly until 23:00 on 3 Nov, then two 6-hourly steps.
function metno() {
    const start = Date.parse("2026-11-02T14:00:00Z");
    const series = [];
    for (let h = 0; h <= 32; h++)
        series.push(step(start + h * HOUR_MS, 5 + h % 3, h === 15 ? { next12: { summary: { symbol_code: "rain" } } } : {}));
    const last = start + 32 * HOUR_MS;
    series.push(step(last + 6 * HOUR_MS, 2, { next1: null, next6: { summary: { symbol_code: "lightsnowshowers_night" }, details: { air_temperature_min: -1, air_temperature_max: 3 } } }));
    series.push(step(last + 12 * HOUR_MS, 4, { next1: null }));
    return JSON.stringify({ properties: { timeseries: series } });
}

test("metno requests round coordinates to four decimals and identify the client", () => {
    const req = providers.request("metno", 47.0215901, 7.4505443);
    assert.match(req.url, /lat=47\.0216&lon=7\.4505$/);
    assert.ok(req.userAgent);
});

test("metno symbols map to WMO codes regardless of the time-of-day suffix", () => {
    assert.deepEqual(Array.from(["clearsky_night", "partlycloudy_day", "heavyrainshowers_polartwilight", "lightsleetshowersandthunder_day", "sleet", "fog", "unknown"].map(providers.metnoCode)), [0, 2, 82, 95, 66, 45, null]);
});

test("metno hourly data is indexed from local midnight and ends with the hourly steps", () => {
    const data = providers.parse("metno", metno(), 47, 7.45, Date.parse("2026-11-02T14:20:00Z"));
    assert.equal(data.hourly.time[0], "2026-11-02T00:00");
    assert.equal(data.hourly.time.at(-1), "2026-11-03T23:00");
    assert.equal(data.hourly.temperature_2m[0], data.hourly.temperature_2m[15]);
    assert.equal(data.hourly.wind_speed_10m[15], 18);
});

test("metno current hour lines up with the hourly forecast", () => {
    const now = Date.parse("2026-11-02T14:20:00Z");
    const weather = weatherData.fromOpenMeteo(providers.parse("metno", metno(), 47, 7.45, now), labels);
    assert.equal(weather.currentHourIndex, 15);
    assert.equal(weather.isDay, true);
    assert.equal(weather.humidity, 70);
    assert.equal(weather.visibility, null);
});

test("metno daily values use the daytime summary and the 6-hourly extremes", () => {
    const daily = providers.parse("metno", metno(), 47, 7.45, Date.parse("2026-11-02T14:20:00Z")).daily;
    assert.deepEqual(Array.from(daily.time), ["2026-11-02", "2026-11-03", "2026-11-04"]);
    assert.equal(daily.weather_code[1], 63);
    assert.equal(daily.temperature_2m_min[2], -1);
    assert.ok(daily.sunrise[1] < daily.sunset[1]);
});

test("parse rejects a provider response without data", () => {
    assert.throws(() => providers.parse("metno", "{\"properties\":{\"timeseries\":[]}}", 47, 7.45, Date.now()));
    assert.throws(() => weatherData.fromOpenMeteo(providers.parse("openmeteo", "{}", 47, 7.45, Date.now()), labels));
});
