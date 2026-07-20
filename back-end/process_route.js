const toGeoJSON = require("togeojson");
const { DOMParser } = require("xmldom");
const fs = require("fs");

/**
 * Calculates the position of the ghost runner throughout a given route in 50ms intervals.
 * @param filepath - The filepath containing the gpx route file.
 * @param pace - The desired pace of the ghost runner. If this value is "00:00", then the pace of the original run is used instead.
 * @returns An array in the format [(Longitude, latitude)] of the ghost runner's positions
 */
function getRoute(filepath, pace) {
  const feature = toJSON(filepath).features[0];
  const points = feature.geometry.coordinates;
  console.log(points);
  // Throws error when input route is too short
  if (points.length < 5) {
    throw new Error("GPX route must contain at least 5 points");
  }
  // When the input pace is 00:00, it flags that the ghost runner should mimic the original gpx file pace.
  if (pace == "00:00") {
    const times = feature.properties.coordTimes;
    const startMs = new Date(times[0]).getTime();
    const secondsPassed = times.map(
      (t) => (new Date(t).getTime() - startMs) / 1000,
    );
    const route = interpolateTo50ms(points, secondsPassed);
    const smoothedRoute = smoothRoute(route);
    return smoothedRoute;
    // The ghost runner runs at a desired input pace.
  } else {
    const route = setSpeedRoute(points, parseSpeed(pace));
    return route;
  }
}

/**
 * Converts a gpx file, from a given filepath, to a GeoJSON file.
 * @param {*} filepath - The filepath containing the gpx file.
 * @returns the converted GeJSON file.
 */
function toJSON(filepath) {
  const gpxString = fs.readFileSync(filepath, "utf8");
  const dom = new DOMParser().parseFromString(gpxString, "text/xml");
  const geojson = toGeoJSON.gpx(dom);
  return geojson;
}

/**
 * Uses linear interpolation to estimate the ghost runner's position between gps points, at 50ms time intervals.
 * @param {*} points - An array of points which signifies the runner's positions throughout the original route.
 * @param {*} secondsPassed - An array which corresponds to how many seconds have passed since the start of the run to when the position was recorded.
 * @returns An array of interpolated points.
 */
function interpolateTo50ms(points, secondsPassed) {
  const route = [];
  for (let i = 0; i < points.length - 1; i++) {
    const deltaTime = secondsPassed[i + 1] - secondsPassed[i];
    if (deltaTime < 0.025) {
      continue;
    }

    const [lon1, lat1] = points[i];
    const [lon2, lat2] = points[i + 1];
    const cycles = Math.round(deltaTime / 0.05);
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
 * Takes a pace given in string format "xx:xx" measured in minutes per kilometre, and returns the speed in metres/second.
 * @param {*} pace - The input pace string. For example "05:34" is equivalent to a pace of 5 minutes and 34 seconds per kilometre.
 * @returns The desired ghost runner's speed in m/s.
 */
function parseSpeed(pace) {
  const minutes = parseInt(pace.slice(0, 2), 10);
  const seconds = parseInt(pace.slice(3), 10);
  const time = seconds + 60 * minutes;
  return (1 / time) * 1000;
}

/**
 * Smooths the route by averaging the ghost runner's pace over 50m segments.
 * @param {*} points - The array of points in the route in 50ms intervals.
 * @returns An array of smoothed points.
 */

function smoothRoute(points) {
  // Split the route into 50m segments.

  const segments = [];
  let currentSegment = [points[0]];
  let distAccum = 0;

  for (let i = 1; i < points.length; i++) {
    const d = distance(points[i - 1], points[i]);
    distAccum += d;

    if (distAccum >= 50) {
      segments.push(currentSegment);
      currentSegment = [points[i]];
      distAccum = 0;
    } else {
      currentSegment.push(points[i]);
    }
  }
  if (currentSegment.length > 0) segments.push(currentSegment);

  // Redistribute each segment at constant pace.
  const smoothedRoute = [];
  let key = 0;

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
 * @param {*} points The array of points in the route in 50ms intervals.
 * @param {*} speed The ghost runner's desired speed in m/s
 * @returns An array of ghost runner positions.
 */
function setSpeedRoute(points, speed) {
  const pacedRoute = [];
  const distPerTick = speed * 0.05; // metres covered per 50ms
  let distAccum = 0;
  let tickDistAccum = 0;

  pacedRoute.push(points[0]);

  for (let i = 1; i < points.length; i++) {
    const segDist = distance(points[i - 1], points[i]);
    distAccum += segDist;

    while (tickDistAccum + distPerTick <= distAccum) {
      tickDistAccum += distPerTick;

      let walked = 0;
      for (let k = 1; k < points.length; k++) {
        const d = distance(points[k - 1], points[k]);
        if (walked + d >= tickDistAccum) {
          const t = (tickDistAccum - walked) / d;
          pacedRoute.push([
            points[k - 1][0] + (points[k][0] - points[k - 1][0]) * t,
            points[k - 1][1] + (points[k][1] - points[k - 1][1]) * t,
          ]);
          break;
        }
        walked += d;
      }
    }
  }

  const [finalLon, finalLat] = points[points.length - 1];
  pacedRoute.push([finalLon, finalLat]);
  return pacedRoute;
}

/**
 * Calculates the euclidean distance between two points in meters, given in lattitude and longitude.
 * @param {*} p1 - The first points.
 * @param {*} p2 - The second point.
 * @returns Distance between the two points in meters.
 */
function distance(p1, p2) {
  const dx = (p2[0] - p1[0]) * 111320 * Math.cos((p1[1] * Math.PI) / 180);
  const dy = (p2[1] - p1[1]) * 111320;
  return Math.sqrt(dx * dx + dy * dy);
}

module.exports = { getRoute, toJSON, interpolateTo50ms, parseSpeed, smoothRoute, setSpeedRoute, distance };
