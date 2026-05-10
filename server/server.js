const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const axios = require("axios");
const cors = require("cors");
const mongoose = require("mongoose");
require("dotenv").config();
const authRoutes = require("./routes/auth");
const nodemailer = require("nodemailer");
const User = require("./models/User");

const app = express();
const server = http.createServer(app); // Correctly wrap the app

const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST", "PUT"],
  },
});

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

app.use("/", authRoutes);

// --- SOCKET.IO REAL-TIME LOGIC ---
io.on("connection", (socket) => {
  console.log(`🔌 User Connected: ${socket.id}`);

  // When a Responder or Victim enters the Map Page, they join a room named after the Victim's ID
  socket.on("join_emergency", (emergencyId) => {
    socket.join(emergencyId);
    console.log(`📡 Socket ${socket.id} joined room: ${emergencyId}`);
  });

  // Victim updates their live location -> Emits only to people in that room (the assigned Responder)
  socket.on("update_location", (data) => {
    // data: { emergencyId, lat, lng, heading }
    socket.to(data.emergencyId).emit("location_received", data);
  });

  // Two-way Chat inside the specific emergency room
  socket.on("send_message", (data) => {
    io.to(data.emergencyId).emit("message_received", data);
  });

  socket.on("disconnect", () => {
    console.log("❌ User Disconnected");
  });
});

// --- MONGODB CONNECTION ---
if (MONGO_URI) {
  mongoose
    .connect(MONGO_URI)
    .then(() => console.log("✅ Connected to MongoDB Atlas"))
    .catch((err) => console.error("❌ MongoDB Connection Error:", err));
}

// 1. Fetch Nearby Places
app.get("/places", async (req, res) => {
  const { lat, lng, type } = req.query;
  try {
    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&rankby=distance&type=${type}&key=${GOOGLE_MAPS_API_KEY}`;
    const response = await axios.get(url);
    res.json({
      results: response.data.results || [],
      status: response.data.status,
    });
  } catch (error) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// 2. Fetch Directions
app.get("/directions", async (req, res) => {
  const { origin, destination } = req.query;
  try {
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&mode=driving&key=${GOOGLE_MAPS_API_KEY}`;
    const response = await axios.get(url);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: "Failed to fetch directions" });
  }
});

// 3. Update User Safety Status & Notify Responders
app.put("/user/status", async (req, res) => {
  const { userId, isSafe, lastLocation } = req.body;
  try {
    const user = await User.findByIdAndUpdate(
      userId,
      { isSafe: isSafe, lastLocation: lastLocation },
      { new: true },
    );

    // If the user toggles to "NOT safe" (Help Needed)
    if (!isSafe) {
      // 1. Global Alert: Tell all responders a new emergency exists
      io.emit("new_emergency_alert", {
        userId: user._id,
        userName: user.name,
        location: lastLocation,
      });

      // 2. Room Event: If a responder is already in the room, update their UI
      io.to(userId.toString()).emit("status_changed", { isSafe: false });
    } else {
      // If they toggle back to safe, clear the alert for responders
      io.to(userId.toString()).emit("status_changed", { isSafe: true });
    }

    res.json({ message: "Status updated", isSafe: user.isSafe });
  } catch (err) {
    res.status(500).json({ error: "Failed to update status" });
  }
});

app.get("/user/:id", async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select("-password");
    if (!user) return res.status(404).json({ error: "User not found" });
    res.json(user);
  } catch (err) {
    res.status(400).json({ error: "Invalid User ID" });
  }
});

// --- SOS EMAIL TRIGGER ---
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: { user: process.env.EMAIL_USER, pass: process.env.EMAIL_PASS },
});

app.post("/trigger-sos", async (req, res) => {
  const { userId, locationLink } = req.body;
  try {
    const user = await User.findById(userId);
    if (!user || user.emergencyContacts.length === 0)
      return res.status(404).json({ error: "No contacts" });

    const recipientEmails = user.emergencyContacts
      .map((c) => c.email)
      .filter((e) => e)
      .join(", ");
    await transporter.sendMail({
      from: `"EmergenSeek" <${process.env.EMAIL_USER}>`,
      to: recipientEmails,
      subject: `🚨 SOS Alert: ${user.name} needs help!`,
      html: `<p><b>${user.name}</b> requested help.</p><p><a href="${locationLink}">View Location</a></p>`,
    });
    res.json({ message: "SOS Emails sent!" });
  } catch (err) {
    res.status(500).json({ error: "Email failed" });
  }
});

// CRITICAL CHANGE: Listen on 'server', not 'app'
const PORT = process.env.PORT || 3000;
server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server + Socket.io listening on port ${PORT}`);
});
