const express = require("express");
const axios = require("axios");
const cors = require("cors");
const mongoose = require("mongoose");
require("dotenv").config();

const app = express();

// --- CORS CONFIGURATION ---
// This configuration allows Flutter Web to communicate without "Preflight" blocks
app.use(
  cors({
    origin: "*", // Allows all origins
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowedHeaders: [
      "Content-Type",
      "Authorization",
      "Accept",
      "X-Requested-With",
    ],
    credentials: true,
  }),
);

app.use(express.json());

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;
const MONGO_URI = process.env.MONGO_URI;

// --- MONGODB CONNECTION ---
if (MONGO_URI) {
  mongoose
    .connect(MONGO_URI)
    .then(() => console.log("✅ Connected to MongoDB Atlas"))
    .catch((err) => console.error("❌ MongoDB Connection Error:", err));
} else {
  console.warn("⚠️ MONGO_URI not found in environment variables.");
}

// 1. Fetch Nearby Emergency Places
app.get("/places", async (req, res) => {
  const { lat, lng, type } = req.query;

  if (!lat || !lng || !type) {
    return res
      .status(400)
      .json({ error: "Missing parameters: lat, lng, and type are required." });
  }

  try {
    // Rounding coordinates to prevent floating point errors in URL
    const cleanLat = parseFloat(lat).toFixed(6);
    const cleanLng = parseFloat(lng).toFixed(6);

    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${cleanLat},${cleanLng}&radius=5000&type=${type}&key=${GOOGLE_MAPS_API_KEY}`;

    const response = await axios.get(url);

    if (
      response.data.status !== "OK" &&
      response.data.status !== "ZERO_RESULTS"
    ) {
      console.error("Google Places Error Status:", response.data.status);
      return res.status(400).json({
        error:
          response.data.error_message ||
          `Google Error: ${response.data.status}`,
      });
    }

    res.json({
      results: response.data.results || [],
      status: response.data.status,
    });
  } catch (error) {
    console.error("Places Fetch Error:", error.message);
    res.status(500).json({ error: "Server error fetching places" });
  }
});

// 2. Fetch Directions
app.get("/directions", async (req, res) => {
  const { origin, destination } = req.query;

  if (!origin || !destination) {
    return res
      .status(400)
      .json({ error: "Missing path points: origin and destination required." });
  }

  try {
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&mode=driving&key=${GOOGLE_MAPS_API_KEY}`;

    const response = await axios.get(url);

    if (response.data.status !== "OK") {
      console.log(`❌ Directions Failed: ${response.data.status}`);
      return res.status(400).json({
        error:
          response.data.error_message ||
          `Google Error: ${response.data.status}`,
        status: response.data.status,
      });
    }

    res.json(response.data);
  } catch (error) {
    console.error("Server Direction Error:", error.message);
    res.status(500).json({ error: "Failed to fetch directions" });
  }
});

// Root route for health check
app.get("/", (req, res) => {
  res.send("🚀 EmergenSeek Backend is running!");
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server live on port ${PORT}`);
});
