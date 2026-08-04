import express from "express";
import multer from "multer";
import cors from "cors";
import fs from "fs";
import os from "os";
import { getRoute } from "./process_route.js";


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

app.post("/api/runs/upload", upload.single("gpxFile"), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "No file uploaded" });
  }
  try {
    const pace = req.body.pace;
    const dummyRoute = req.body.dummyRoute;
    const route = getRoute(req.file.path, pace, dummyRoute);
    res.json({ route });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to parse request" });
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
