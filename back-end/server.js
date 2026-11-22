const express = require("express");
const multer = require("multer");
const cors = require("cors");
const fs = require("fs");
const os = require("os");
const { getRoute, RouteError } = require("./process_route.js");

const app = express();
app.use(cors());

// Store uploads in the OS temp dir, deleted after processing.
const upload = multer({
  dest: os.tmpdir(),
  limits: { fileSize: 20 * 1024 * 1024 }, // 20MB safety cap
  fileFilter: (req, file, cb) => {
    if (!file.originalname.toLowerCase().endsWith(".gpx")) {
      return cb(new Error("Only .gpx files are accepted"));
    }
    cb(null, true);
  },
});

app.get("/", (req, res) => {
  res.send("Server is working!");
});

app.post("/api/runs/upload", upload.single("gpxFile"), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "No file uploaded" });
  }
  try {
    res.json(getRoute(req.file.path, req.body?.pace));
  } catch (err) {
    if (err instanceof RouteError) {
      res.status(400).json({ error: err.message });
    } else {
      console.error(err);
      res.status(500).json({ error: "Failed to process route" });
    }
  } finally {
    fs.unlink(req.file.path, () => {}); // cleanup temp file either way
  }
});

// Multer errors (bad file type, too large) land here instead of crashing.
// Express needs all 4 arguments to treat this as an error handler.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  res.status(400).json({ error: err.message });
});

if (require.main === module) {
  app.listen(3000, () => console.log("Server running on port 3000"));
}

module.exports = app;
