import toGeoJSON from "togeojson";
import { DOMParser } from "xmldom";
import fs from "fs";

/**
 * When given a gpx files, it returns an array of points over the route.
 * @returns The array of points for the route, in 50ms intervals, and smoothed over 50 meters.
 */
export function getRoute(filepath) {
  const feature = toJSON(filepath).features[0];
  const points = feature.geometry.coordinates;
  const times = feature.properties.coordTimes;

  const startMs = new Date(times[0]).getTime();
  const secondsPassed = times.map(
    (t) => (new Date(t).getTime() - startMs) / 1000,
  );
  const route = interpolateTo50ms(points, secondsPassed);
  const smoothedRoute = smoothRoute(route);
  return smoothedRoute; 
}

/**
 * Converts a gpx file, from a given filepath, to a GeoJSON file
 * @param {*} filepath - The filepath containing the gpx file
 * @returns the converted GeJSON file
 */
function toJSON(filepath) {
  const gpxString = fs.readFileSync(filepath, "utf8");
  const dom = new DOMParser().parseFromString(gpxString, "text/xml");
  const geojson = toGeoJSON.gpx(dom);
  return geojson;
}

/**
 * Uses linear interpolation to estimate the ghost runner's position between gps points, at 50ms intervals
 * @param {*} points - The raw points from the gpx route
 * @param {*} secondsPassed - The number of seconds which have passed by the time its corresponding point has been documented.
 * @returns An array of interpolated points
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

  // add final point
  const [finalLon, finalLat] = points[points.length - 1];
  route.push([finalLon, finalLat]);
  return route;
}

/**
 * Smooths the route by averaging the ghost runner's pace over 50m segments.
 * @param {*} points - The array of points in the route in 50ms intervals.
 * @returns An array of smoothed points.
 */

function smoothRoute(points) {
  // First pass: split points into 50m segments

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

  // Second pass: redistribute each segment at constant pace
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
 * Calculates the euclidean distance between two points, given in lattitude and longitude.
 * @param {*} p1 - The first points.
 * @param {*} p2 - The second point.
 * @returns Distance between the two points
 */
function distance(p1, p2) {
  const dx = (p2[0] - p1[0]) * 111320 * Math.cos((p1[1] * Math.PI) / 180);
  const dy = (p2[1] - p1[1]) * 111320;
  return Math.sqrt(dx * dx + dy * dy);
}


