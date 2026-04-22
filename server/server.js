const express = require("express");
const axios = require("axios");
const cors = require("cors");
const mongoose = require("mongoose");
require("dotenv").config();

const app = express();

// --- CORS CONFIGURATION ---
app.use(
  cors({
    origin: "*",
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

// Note: Ensure GOOGLE_API_KEY is set in your Render Environment Variables
const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_API_KEY;
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

  if (!GOOGLE_MAPS_API_KEY) {
    console.error(
      "❌ API KEY MISSING: Check your .env or Render Environment Variables.",
    );
    return res
      .status(500)
      .json({ error: "Server API Key configuration error." });
  }

  try {
    // Constructing the URL for the Places API (Nearby Search)
    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=5000&type=${type}&key=${GOOGLE_MAPS_API_KEY}`;

    const response = await axios.get(url);

    // If Google returns an error status (like REQUEST_DENIED)
    if (
      response.data.status !== "OK" &&
      response.data.status !== "ZERO_RESULTS"
    ) {
      console.error(`❌ Google Places API Error: ${response.data.status}`);
      console.error(
        `Reason: ${response.data.error_message || "No specific message provided"}`,
      );

      return res.status(400).json({
        status: response.data.status,
        error: response.data.error_message || "Google API request was denied.",
      });
    }

    res.json({
      results: response.data.results || [],
      status: response.data.status,
    });
  } catch (error) {
    console.error("Places Fetch Error:", error.message);
    res.status(500).json({ error: "Internal server error fetching places" });
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
      console.error(`❌ Directions API Error: ${response.data.status}`);
      console.error(
        `Reason: ${response.data.error_message || "No specific message provided"}`,
      );

      return res.status(400).json({
        status: response.data.status,
        error: response.data.error_message || "Directions request was denied.",
      });
    }

    res.json(response.data);
  } catch (error) {
    console.error("Server Direction Error:", error.message);
    res.status(500).json({ error: "Failed to fetch directions" });
  }
});

// Health check route
app.get("/", (req, res) => {
  res.send("🚀 EmergenSeek Backend is running!");
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server live on port ${PORT}`);
});
