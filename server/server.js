const express = require("express");
const axios = require("axios");
const cors = require("cors");
const mongoose = require("mongoose"); // Added Mongoose
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json());

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;
const MONGO_URI = process.env.MONGO_URI; // Use the URI from Render/Env

// --- MONGODB CONNECTION ---
mongoose
  .connect(MONGO_URI)
  .then(() => console.log("✅ Connected to MongoDB Atlas"))
  .catch((err) => console.error("❌ MongoDB Connection Error:", err));

// 1. Fetch Nearby Emergency Places
app.get("/places", async (req, res) => {
  const { lat, lng, type } = req.query;
  if (!lat || !lng || !type)
    return res.status(400).json({ error: "Missing parameters" });

  try {
    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=5000&type=${type}&key=${GOOGLE_MAPS_API_KEY}`;
    const response = await axios.get(url);

    // Check if Google returned an error (like Invalid Key)
    if (
      response.data.status !== "OK" &&
      response.data.status !== "ZERO_RESULTS"
    ) {
      console.error("Google Places Error:", response.data.error_message);
      return res.status(400).json({ error: response.data.error_message });
    }

    res.json({ results: response.data.results, status: response.data.status });
  } catch (error) {
    res.status(500).json({ error: "Server error fetching places" });
  }
});

// 2. Fetch Directions (The part causing your "Line" error)
app.get("/directions", async (req, res) => {
  const { origin, destination } = req.query;
  if (!origin || !destination)
    return res.status(400).json({ error: "Missing path points" });

  try {
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&mode=driving&key=${GOOGLE_MAPS_API_KEY}`;
    const response = await axios.get(url);

    // If Google says "NOT_FOUND" or "ZERO_RESULTS", this is why your line won't draw
    if (response.data.status !== "OK") {
      console.log(
        `❌ Directions Failed: ${response.data.status} - ${response.data.error_message}`,
      );
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

// Use Render's dynamic port or default to 3000
const PORT = process.env.PORT || 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server live on port ${PORT}`);
});
