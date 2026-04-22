const express = require("express");
const axios = require("axios");
const cors = require("cors");
const mongoose = require("mongoose");
require("dotenv").config();
const authRoutes = require("./routes/auth");
const nodemailer = require("nodemailer");
const User = require("./models/User");

const app = express();

// --- CORS CONFIGURATION ---
// Origins are set to "*" for development flexibility with Flutter/Web
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

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_API_KEY;
const MONGO_URI = process.env.MONGO_URI;

// --- AUTH ROUTES ---
app.use("/", authRoutes);

// --- MONGODB CONNECTION ---
if (MONGO_URI) {
  mongoose
    .connect(MONGO_URI)
    .then(() => console.log("✅ Connected to MongoDB Atlas"))
    .catch((err) => console.error("❌ MongoDB Connection Error:", err));
} else {
  console.warn("⚠️ MONGO_URI not found in environment variables.");
}

// 1. Fetch Nearby Emergency Places (Optimized for Nearest)
app.get("/places", async (req, res) => {
  const { lat, lng, type } = req.query;

  if (!lat || !lng || !type) {
    return res
      .status(400)
      .json({ error: "Missing parameters: lat, lng, and type are required." });
  }

  if (!GOOGLE_MAPS_API_KEY) {
    return res
      .status(500)
      .json({ error: "Google API Key is not configured on the server." });
  }

  try {
    /**
     * rankby=distance: Returns results in order of proximity.
     * Note: 'radius' MUST NOT be used when 'rankby=distance' is present.
     */
    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&rankby=distance&type=${type}&key=${GOOGLE_MAPS_API_KEY}`;

    const response = await axios.get(url);

    // Validation for Google-specific error statuses
    if (
      response.data.status !== "OK" &&
      response.data.status !== "ZERO_RESULTS"
    ) {
      console.error(`❌ Google Places API Error: ${response.data.status}`);
      return res.status(400).json({
        status: response.data.status,
        error: response.data.error_message || "Google API request was denied.",
      });
    }

    // Return results to Flutter
    res.json({
      results: response.data.results || [],
      status: response.data.status,
    });
  } catch (error) {
    console.error("Places Fetch Error:", error.message);
    res.status(500).json({ error: "Internal server error fetching places" });
  }
});

// 2. Fetch Directions (Driving Mode)
app.get("/directions", async (req, res) => {
  const { origin, destination } = req.query;

  if (!origin || !destination) {
    return res
      .status(400)
      .json({ error: "Missing path points: origin and destination required." });
  }

  try {
    // mode=driving is essential for emergency routing
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&mode=driving&key=${GOOGLE_MAPS_API_KEY}`;

    const response = await axios.get(url);

    if (response.data.status !== "OK") {
      console.error(`❌ Directions API Error: ${response.data.status}`);
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

// --- Update Emergency Contacts ---
app.put("/user/contacts", async (req, res) => {
  const { userId, contacts } = req.body; // contacts should be an array
  try {
    const user = await User.findByIdAndUpdate(
      userId,
      { emergencyContacts: contacts },
      { new: true },
    );
    res.json({
      message: "Contacts updated successfully",
      contacts: user.emergencyContacts,
    });
  } catch (err) {
    res.status(500).json({ error: "Failed to update contacts" });
  }
});

// --- Get User Profile (to load existing contacts) ---
app.get("/user/:id", async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select("-password");
    if (!user) return res.status(404).json({ error: "User not found" });
    res.json(user);
  } catch (err) {
    // If ID is malformed, it throws an error
    res.status(400).json({ error: "Invalid User ID format" });
  }
});

// --- EMAIL CONFIGURATION ---
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER, // Your Gmail address
    pass: process.env.EMAIL_PASS, // Your Google App Password
  },
});

// --- SOS TRIGGER ROUTE ---
app.post("/trigger-sos", async (req, res) => {
  const { userId, locationLink } = req.body;

  try {
    const user = await User.findById(userId);
    if (!user || user.emergencyContacts.length === 0) {
      return res.status(404).json({ error: "No contacts found" });
    }

    // Extract all emails into a string (e.g., "mom@mail.com, dad@mail.com")
    const recipientEmails = user.emergencyContacts
      .map((c) => c.email)
      .filter((email) => email) // Remove empty emails
      .join(", ");

    const mailOptions = {
      from: `"EmergenSeek" <${process.env.EMAIL_USER}>`,
      to: recipientEmails,
      subject: "🚨 EMERGENCY SOS - [User Name] Needs Help!",
      html: `
        <h2>Emergency Alert!</h2>
        <p>This is an automated alert from <b>EmergenSeek</b>.</p>
        <p>Your contact is requesting immediate assistance.</p>
        <p><b>Current Location:</b> <a href="${locationLink}">View on Google Maps</a></p>
      `,
    };

    await transporter.sendMail(mailOptions);
    res.json({ message: "SOS Emails sent successfully!" });
  } catch (err) {
    console.error("SOS Error:", err);
    res.status(500).json({ error: "Failed to send SOS alerts" });
  }
});

// Root / Health check
app.get("/", (req, res) => {
  res.send("🚀 EmergenSeek Backend is live and sorting by distance!");
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server listening on port ${PORT}`);
});
