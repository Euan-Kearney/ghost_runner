const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  getRoute,
  interpolateRoute,
  parseSpeed,
  smoothRoute,
  setSpeedRoute,
  distance,
  getPercentages,
  RouteError,
} = require("./process_route");

const STRAIGHT_LINE = path.join(__dirname, "example-routes", "straight_line.gpx");
const STRAIGHT_LINE_SECONDS = 80; // 04:59:56 -> 05:01:16

// Writes a GPX with the given [lon, lat, isoTime?] points to a temp file.
function writeGpx(points) {
  const trkpts = points
    .map(
      ([lon, lat, time]) =>
        `<trkpt lat="${lat}" lon="${lon}">${time ? `<time>${time}</time>` : ""}</trkpt>`,
    )
    .join("");
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "gr-")), "r.gpx");
  fs.writeFileSync(
    file,
    `<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>${trkpts}</trkseg></trk></gpx>`,
  );
  return file;
}

const isFinitePoint = ([lon, lat]) => Number.isFinite(lon) && Number.isFinite(lat);

describe("interpolateRoute", () => {
  test("between two separate points", () => {
    const expected = Array.from({ length: 21 }, (_, i) => [expect.closeTo(i * 0.05), 0]);
    expect(interpolateRoute([[0, 0, 0], [1, 0, 0]], [0, 1], 0.05)).toStrictEqual(expected);
  });

  test("between the same two points", () => {
    const expected = Array.from({ length: 21 }, () => [0, 0]);
    expect(interpolateRoute([[0, 0, 0], [0, 0, 0]], [0, 1], 0.05)).toStrictEqual(expected);
  });

  test("six points", () => {
    const expected = Array.from({ length: 101 }, (_, i) => [expect.closeTo(i * 0.1), 0]);
    const points = [0, 2, 4, 6, 8, 10].map((x) => [x, 0, 0]);
    expect(interpolateRoute(points, [0, 1, 2, 3, 4, 5], 0.05)).toStrictEqual(expected);
  });

  test("2D", () => {
    expect(interpolateRoute([[0, 0], [2, 4]], [0, 2], 0.5)).toStrictEqual([
      [0, 0],
      [0.5, 1],
      [1, 2],
      [1.5, 3],
      [2, 4],
    ]);
  });

  test("skips points recorded at the same time", () => {
    expect(interpolateRoute([[0, 0], [5, 5], [1, 0]], [0, 0, 1], 0.5)).toStrictEqual([
      [5, 5],
      [3, 2.5],
      [1, 0],
    ]);
  });
});

describe("parseSpeed", () => {
  test.each([
    ["05:00", 1000 / 300],
    ["5:30", 1000 / 330],
    ["10:00", 1000 / 600],
  ])("%s", (pace, speed) => expect(parseSpeed(pace)).toBeCloseTo(speed));

  test.each(["abc", "5:75", "", "00:00", "5", "-5:00"])("rejects %p", (pace) => {
    expect(() => parseSpeed(pace)).toThrow(RouteError);
  });
});

describe("distance", () => {
  test("0.001 degrees of latitude is ~111m", () => {
    expect(distance([0, 0], [0, 0.001])).toBeCloseTo(111.32, 1);
  });
  test("same point is 0", () => expect(distance([1, 1], [1, 1])).toBe(0));
});

describe("setSpeedRoute", () => {
  // ~100m due east along the equator
  const end = 100 / 111320;
  const points = [[0, 0], [end / 2, 0], [end / 2, 0], [end, 0]];

  test("spaces points by speed * 50ms and keeps endpoints", () => {
    const route = setSpeedRoute(points, 2); // 0.1m per tick
    expect(route[0]).toEqual([0, 0]);
    expect(route[route.length - 1]).toEqual([end, 0]);
    expect(route.length).toBeGreaterThanOrEqual(1000);
    expect(route.length).toBeLessThanOrEqual(1002);
    for (let i = 1; i < route.length - 1; i++) {
      expect(distance(route[i - 1], route[i])).toBeCloseTo(0.1, 3);
    }
  });

  test("duplicate points never produce NaN", () => {
    expect(setSpeedRoute(points, 3).every(isFinitePoint)).toBe(true);
  });
});

describe("smoothRoute", () => {
  test("keeps the number of points (time) and the start", () => {
    const route = interpolateRoute([[0, 0], [0.001, 0], [0.003, 0]], [0, 10, 20], 0.05);
    const smoothed = smoothRoute(route);
    expect(smoothed).toHaveLength(route.length);
    expect(smoothed[0]).toEqual(route[0]);
    expect(smoothed.every(isFinitePoint)).toBe(true);
  });
});

describe("getPercentages", () => {
  test("goes from 0 to 100 including the last segment", () => {
    const pct = getPercentages([[0, 0], [0.001, 0], [0.002, 0], [0.004, 0]]);
    expect(pct).toHaveLength(4);
    expect(pct[0]).toBe(0);
    expect(pct[1]).toBeCloseTo(25);
    expect(pct[2]).toBeCloseTo(50);
    expect(pct[3]).toBeCloseTo(100);
  });
});

describe("getRoute", () => {
  test("original pace gives a point every 50ms", () => {
    const { route } = getRoute(STRAIGHT_LINE, "00:00");
    expect(route.length).toBeCloseTo(STRAIGHT_LINE_SECONDS / 0.05 + 1, -1);
    expect(route.every(isFinitePoint)).toBe(true);
  });

  test("set pace", () => {
    const { route } = getRoute(STRAIGHT_LINE, "06:00");
    expect(route.length).toBeGreaterThan(100);
    expect(route.every(isFinitePoint)).toBe(true);
  });

  test("rejects a route with fewer than 5 points", () => {
    const file = writeGpx([[0, 0, "2026-01-01T00:00:00Z"], [0, 0.001, "2026-01-01T00:00:10Z"]]);
    expect(() => getRoute(file, "00:00")).toThrow(RouteError);
  });

  test("rejects original pace when the GPX has no timestamps", () => {
    const file = writeGpx([0, 1, 2, 3, 4].map((i) => [0, i * 0.001]));
    expect(() => getRoute(file, "00:00")).toThrow(/timestamps/);
    expect(getRoute(file, "05:00").route.length).toBeGreaterThan(100);
  });

  test("rejects a file that isn't a GPX track", () => {
    const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "gr-")), "x.gpx");
    fs.writeFileSync(file, "not xml at all");
    expect(() => getRoute(file, "00:00")).toThrow(RouteError);
  });
});
