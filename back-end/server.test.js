const fs = require("fs");
const path = require("path");
const app = require("./server");

let server;
let base;
beforeAll((done) => {
  server = app.listen(0, () => {
    base = `http://localhost:${server.address().port}`;
    done();
  });
});
afterAll((done) => {
  server.close(done);
});

function upload(filename, contents, fields = {}) {
  const form = new FormData();
  form.append("gpxFile", new Blob([contents]), filename);
  for (const [k, v] of Object.entries(fields)) form.append(k, v);
  return fetch(`${base}/api/runs/upload`, { method: "POST", body: form });
}

const gpx = fs.readFileSync(path.join(__dirname, "example-routes", "straight_line.gpx"));

test("returns a route for a valid upload", async () => {
  const res = await upload("run.gpx", gpx, { pace: "00:00" });
  expect(res.status).toBe(200);
  const body = await res.json();
  expect(body.route.length).toBeGreaterThan(100);
});

test("defaults to the original pace when no pace is sent", async () => {
  const res = await upload("run.gpx", gpx);
  expect(res.status).toBe(200);
});

test("400 with a message for a bad pace", async () => {
  const res = await upload("run.gpx", gpx, { pace: "fast" });
  expect(res.status).toBe(400);
  expect((await res.json()).error).toMatch(/pace/i);
});

test("400 for a non-gpx file", async () => {
  const res = await upload("run.txt", "hello");
  expect(res.status).toBe(400);
});

test("400 when no file is sent", async () => {
  const res = await fetch(`${base}/api/runs/upload`, { method: "POST", body: new FormData() });
  expect(res.status).toBe(400);
});
