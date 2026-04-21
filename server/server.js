const express = require("express");
const axios = require("axios");
const cors = require("cors");
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json());

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;

// 1. Fetch Nearby Emergency Places
app.get("/places", async (req, res) => {
  const { lat, lng, type } = req.query;

  if (!lat || !lng || !type) {
    return res.status(400).json({ error: "Missing lat, lng, or type" });
  }

  try {
    // We use keyword and type to get better results for Taguig
    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=5000&type=${type}&key=${GOOGLE_MAPS_API_KEY}`;

    const response = await axios.get(url);

    // REQ010: Sending clean results back to Flutter for caching
    res.json({
      results: response.data.results,
      status: response.data.status,
    });
  } catch (error) {
    console.error("Error fetching places:", error.message);
    res.status(500).json({ error: "Failed to fetch places from Google" });
  }
});

// 2. Fetch Directions for Routing
app.get("/directions", async (req, res) => {
  const { origin, destination } = req.query;

  if (!origin || !destination) {
    return res.status(400).json({ error: "Missing origin or destination" });
  }

  try {
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&mode=driving&key=${GOOGLE_MAPS_API_KEY}`;

    const response = await axios.get(url);

    if (response.data.status !== "OK") {
      return res
        .status(400)
        .json({ error: response.data.error_message || "No route found" });
    }

    res.json(response.data);
  } catch (error) {
    console.error("Directions error:", error.message);
    res.status(500).json({ error: "Failed to fetch directions" });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Taguig Emergency Backend running on port ${PORT}`);
});
