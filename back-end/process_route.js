const toGeoJSON = require("togeojson");
const { DOMParser } = require("xmldom");
const fs = require("fs");

const TICK_SECONDS = 0.05; // the app moves the ghost every 50ms

/** Bad user input (bad GPX, bad pace). The server turns these into a 400. */
class RouteError extends Error {}

/**
 * Calculates the ghost runner's position throughout a given route in 50ms intervals.
 * @param filepath - The filepath containing the gpx route file.
 * @param pace - The desired pace ("mm:ss" per km). "00:00" (or empty) uses the original run's pace.
 * @param dummyRoute - "true" to also return runnerRoute: the original run at 1s intervals,
 *   which the app replays as a simulated runner for desk testing.
 * @returns {{route: number[][], runnerRoute?: number[][]}} [longitude, latitude] positions.
 */
function getRoute(filepath, pace = "00:00", dummyRoute = "false") {
  const { points, times } = readTrack(filepath);
  if (points.length < 5) {
    throw new RouteError("GPX route must contain at least 5 points");
  }

  const originalPace = !pace || pace === "00:00";
  let route;
  if (originalPace) {
    route = smoothRoute(interpolateRoute(points, secondsPassed(times, points.length), TICK_SECONDS));
  } else {
    route = setSpeedRoute(points, parseSpeed(pace));
  }

  if (dummyRoute !== "true") return { route };
  const runnerRoute = interpolateRoute(points, secondsPassed(times, points.length), 1.0);
  return { route, runnerRoute };
}

/**
 * Reads the first track of a GPX file. Multi-segment tracks (e.g. a paused run) are joined.
 * @returns {{points: number[][], times: string[] | undefined}}
 */
function readTrack(filepath) {
  const feature = toJSON(filepath).features.find((f) =>
    ["LineString", "MultiLineString"].includes(f.geometry?.type),
  );
  if (!feature) throw new RouteError("No track found in GPX file");
  const multi = feature.geometry.type === "MultiLineString";
  const times = feature.properties.coordTimes;
  return {
    points: multi ? feature.geometry.coordinates.flat() : feature.geometry.coordinates,
    times: multi ? times?.flat() : times,
  };
}

/**
 * Converts a gpx file, from a given filepath, to a GeoJSON object.
 * @param {*} filepath - The filepath containing the gpx file.
 * @returns the converted GeoJSON object.
 */
function toJSON(filepath) {
  const gpxString = fs.readFileSync(filepath, "utf8");
  const dom = new DOMParser({ errorHandler: () => {} }).parseFromString(gpxString, "text/xml");
  return toGeoJSON.gpx(dom);
}

/** Seconds since the first point, for each point. Throws if the GPX has no usable timestamps. */
function secondsPassed(times, count) {
  const ms = (times ?? []).map((t) => new Date(t).getTime());
  if (ms.length !== count || ms.some(Number.isNaN)) {
    throw new RouteError("GPX file has no timestamps, so enter a pace instead");
  }
  return ms.map((t) => (t - ms[0]) / 1000);
}

/**
 * Uses linear interpolation to estimate the ghost runner's position between gps points, to a specified time interval.
 * @param {*} points - An array of points which signifies the runner's positions throughout the original route.
 * @param {*} secondsPassed - An array which corresponds to how many seconds have passed since the start of the run to when the position was recorded.
 * @param {*} interval - Seconds between output points.
 * @returns An array of interpolated points.
 */
function interpolateRoute(points, secondsPassed, interval) {
  const route = [];
  for (let i = 0; i < points.length - 1; i++) {
    const deltaTime = secondsPassed[i + 1] - secondsPassed[i];
    if (deltaTime < interval / 2) {
      continue;
    }

    const [lon1, lat1] = points[i];
    const [lon2, lat2] = points[i + 1];
    const cycles = Math.round(deltaTime / interval);
    for (let j = 0; j < cycles; j++) {
      const t = j / cycles;
      route.push([lon1 + (lon2 - lon1) * t, lat1 + (lat2 - lat1) * t]);
    }
  }

  // Add final point.
  const [finalLon, finalLat] = points[points.length - 1];
  route.push([finalLon, finalLat]);
  return route;
}

/**
 * Takes a pace string "m:ss" or "mm:ss" in minutes per kilometre, and returns the speed in metres/second.
 * @param {*} pace - For example "05:34" is 5 minutes and 34 seconds per kilometre.
 * @returns The desired ghost runner's speed in m/s.
 */
function parseSpeed(pace) {
  const match = /^(\d{1,2}):([0-5]\d)$/.exec(String(pace).trim());
  const seconds = match ? Number(match[1]) * 60 + Number(match[2]) : 0;
  if (seconds === 0) {
    throw new RouteError(`Invalid pace "${pace}": use mm:ss per km, e.g. 05:30`);
  }
  return 1000 / seconds;
}

/**
 * Smooths the route by averaging the ghost runner's pace over 50m segments.
 * Each segment keeps its number of points, so the total time is unchanged.
 * @param {*} points - The array of points in the route in 50ms intervals.
 * @returns An array of smoothed points.
 */
function smoothRoute(points) {
  // Split the route into 50m segments.
  const segments = [];
  let currentSegment = [points[0]];
  let distAccum = 0;

  for (let i = 1; i < points.length; i++) {
    distAccum += distance(points[i - 1], points[i]);

    if (distAccum >= 50) {
      segments.push(currentSegment);
      currentSegment = [points[i]];
      distAccum = 0;
    } else {
      currentSegment.push(points[i]);
    }
  }
  segments.push(currentSegment);

  // Redistribute each segment at constant pace.
  const smoothedRoute = [];
  for (const segment of segments) {
    const n = segment.length;
    const start = segment[0];
    const end = segment[n - 1];

    for (let j = 0; j < n; j++) {
      const t = j / n;
      smoothedRoute.push([
        start[0] + (end[0] - start[0]) * t,
        start[1] + (end[1] - start[1]) * t,
      ]);
    }
  }
  return smoothedRoute;
}

/**
 * Calculates the ghost runner's position at each 50ms interval for a given speed.
 * @param {*} points The GPS points of the route.
 * @param {*} speed The ghost runner's desired speed in m/s
 * @returns An array of ghost runner positions.
 */
function setSpeedRoute(points, speed) {
  const distPerTick = speed * TICK_SECONDS;
  const pacedRoute = [points[0]];
  let nextTickDist = distPerTick; // distance along the route of the next ghost position
  let walked = 0; // distance along the route up to points[i - 1]

  for (let i = 1; i < points.length; i++) {
    const [lon1, lat1] = points[i - 1];
    const [lon2, lat2] = points[i];
    const d = distance(points[i - 1], points[i]);
    while (d > 0 && nextTickDist <= walked + d) {
      const t = (nextTickDist - walked) / d;
      pacedRoute.push([lon1 + (lon2 - lon1) * t, lat1 + (lat2 - lat1) * t]);
      nextTickDist += distPerTick;
    }
    walked += d;
  }

  const [finalLon, finalLat] = points[points.length - 1];
  pacedRoute.push([finalLon, finalLat]);
  return pacedRoute;
}

/**
 * Calculates the euclidean distance between two points in meters, given in [longitude, latitude].
 * shortcut: flat-earth approximation, fine at running scale (errors only matter over many km).
 * @returns Distance between the two points in meters.
 */
function distance(p1, p2) {
  const dx = (p2[0] - p1[0]) * 111320 * Math.cos((p1[1] * Math.PI) / 180);
  const dy = (p2[1] - p1[1]) * 111320;
  return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Calculates the percentage of the route complete at each point along the ghost runner's route
 * @param {*} route - The array of points indicating the ghost runner positions
 * @returns The percentage of the route completed at each point (same length as route).
 */
function getPercentages(route) {
  const cumulative = [0];
  for (let i = 1; i < route.length; i++) {
    cumulative.push(cumulative[i - 1] + distance(route[i - 1], route[i]));
  }
  const total = cumulative[cumulative.length - 1];
  return cumulative.map((d) => (total ? (d / total) * 100 : 0));
}

module.exports = {
  getRoute,
  toJSON,
  interpolateRoute,
  parseSpeed,
  smoothRoute,
  setSpeedRoute,
  distance,
  getPercentages,
  RouteError,
};
