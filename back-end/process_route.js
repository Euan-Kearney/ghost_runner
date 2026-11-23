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
 * @param elevation - With a set pace: slow down uphill and speed up downhill, same average pace.
 * @returns {{route: number[][], noElevation?: true}} [longitude, latitude] positions;
 *   `noElevation` when elevation was asked for but the GPX has none (the ghost runs flat).
 */
function getRoute(filepath, pace = "00:00", elevation = false) {
  const { points, times } = readTrack(filepath);
  if (points.length < 5) {
    throw new RouteError("GPX route must contain at least 5 points");
  }

  if (!pace || pace === "00:00") {
    return {
      route: smoothRoute(interpolateRoute(points, secondsPassed(times, points.length), TICK_SECONDS)),
    };
  }
  const speed = parseSpeed(pace);
  const hills = elevation ? hillSpeeds(points, speed) : null;
  const route = setSpeedRoute(points, hills ?? speed);
  return elevation && !hills ? { route, noElevation: true } : { route };
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
 * @param {number | number[]} speed The ghost runner's speed in m/s, or one per segment (points[i] -> points[i + 1]).
 * @returns An array of ghost runner positions.
 */
function setSpeedRoute(points, speed) {
  const pacedRoute = [points[0]];
  let nextTick = TICK_SECONDS; // time of the next ghost position
  let elapsed = 0; // time to reach points[i - 1]

  for (let i = 1; i < points.length; i++) {
    const [lon1, lat1] = points[i - 1];
    const [lon2, lat2] = points[i];
    const d = distance(points[i - 1], points[i]);
    const dt = d / (Array.isArray(speed) ? speed[i - 1] : speed);
    while (d > 0 && nextTick <= elapsed + dt) {
      const t = (nextTick - elapsed) / dt;
      pacedRoute.push([lon1 + (lon2 - lon1) * t, lat1 + (lat2 - lat1) * t]);
      nextTick += TICK_SECONDS;
    }
    if (d > 0) elapsed += dt;
  }

  const [finalLon, finalLat] = points[points.length - 1];
  pacedRoute.push([finalLon, finalLat]);
  return pacedRoute;
}

const MAX_GRADE = 0.3; // steeper is GPS noise (or not running)

/**
 * Time per metre on a grade (rise / run), relative to flat. A moderate curve like Strava's
 * grade-adjusted pace: +10% takes 1.28x, -10% 0.88x, and the speed-up bottoms out at -12.5%
 * (steeper descents need braking).
 */
function gradeFactor(grade) {
  const g = Math.min(MAX_GRADE, Math.max(-MAX_GRADE, grade));
  return 1 + 2 * g + 8 * g * g;
}

/**
 * Speed for each segment (points[i] -> points[i + 1]) so the ghost slows uphill and speeds up
 * downhill, while the whole route still takes the same time as running it flat at `speed`.
 * @returns {number[] | null} m/s per segment, or null if any point has no elevation.
 */
function hillSpeeds(points, speed) {
  if (!points.every((p) => Number.isFinite(p[2]))) return null;
  const along = [0];
  for (let i = 1; i < points.length; i++) {
    along.push(along[i - 1] + distance(points[i - 1], points[i]));
  }

  // GPS elevation is noisy: use the mean elevation within 50m either side.
  let lo = 0;
  let hi = 0;
  let sum = 0;
  const ele = along.map((s) => {
    while (hi < points.length && along[hi] <= s + 50) sum += points[hi++][2];
    while (along[lo] < s - 50) sum -= points[lo++][2];
    return sum / (hi - lo);
  });

  const factors = [];
  let weighted = 0; // sum of distance * factor
  for (let i = 1; i < points.length; i++) {
    const d = along[i] - along[i - 1];
    const f = d > 0 ? gradeFactor((ele[i] - ele[i - 1]) / d) : 1;
    factors.push(f);
    weighted += d * f;
  }
  // Scale so the total time is still distance / speed.
  const total = along[along.length - 1];
  return factors.map((f) => (speed * weighted) / (total * f));
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
  gradeFactor,
  hillSpeeds,
  RouteError,
};
