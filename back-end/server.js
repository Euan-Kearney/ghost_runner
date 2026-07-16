import express from "express";
import multer from "multer";
import cors from "cors";
import fs from "fs";
import os from "os";
import { getRoute } from "./process_route.js";


const app = express();

// Needed if you're running `flutter run -d chrome` — otherwise the
// browser will block the request as a cross-origin call.
app.use(cors());

// Store uploads in the OS temp dir; we delete them right after processing.
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

app.post("/api/runs/upload", upload.single("gpxFile"), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "No file uploaded" });
  }

  try {
    const route = getRoute(req.file.path);
    res.json({ route });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to parse GPX file" });
  } finally {
    fs.unlink(req.file.path, () => {}); // cleanup temp file either way
  }
});

// Multer errors (bad file type, too large) land here instead of crashing
app.use((err, req, res, next) => {
  res.status(400).json({ error: err.message });
});

app.listen(3000, () => console.log("Server running on port 3000"));

app.get("/", (req, res) => {
    res.send("Server is working!");
});
