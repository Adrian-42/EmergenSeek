const express = require("express");
const http = require("http");
const { Server } = require("socket.io"); // Correct import for v4+
const axios = require("axios");
const cors = require("cors");
const mongoose = require("mongoose");
require("dotenv").config();
const nodemailer = require("nodemailer");

// Route Imports
const authRoutes = require("./routes/auth");
const userRoutes = require("./routes/userRoutes");
const User = require("./models/User");

const app = express();
const server = http.createServer(app);

// Initialize Socket.io
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST", "PUT", "DELETE"],
  },
});
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "emergenseek000@gmail.com", // Your Gmail address
    pass: "sjyc aqal opec psjh", // Your Gmail App Password
  },
});
// Middleware
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

// Pass 'io' to the request object so routes can use it
app.set("socketio", io);

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_API_KEY;
const MONGO_URI = process.env.MONGO_URI;

// --- ROUTES ---
app.use("/", authRoutes);
app.use("/user", userRoutes); // All user-related endpoints now prefixed with /user

// --- SHARED UTILITY ROUTES (Maps/Places) ---
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

app.get("/get-directions", async (req, res) => {
  const { origin, destination } = req.query;
  try {
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&mode=driving&key=${GOOGLE_MAPS_API_KEY}`;
    const response = await axios.get(url);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: "Failed to fetch directions" });
  }
});

app.get("/active-emergencies", async (req, res) => {
  try {
    const activeUsers = await User.find({ isSafe: false })
      .select("-password")
      .sort({ updatedAt: -1 });
    const formattedEmergencies = activeUsers.map((user) => ({
      userId: user._id,
      userName: user.name,
      location: user.lastLocation,
      phoneNumber: user.phoneNumber,
    }));
    res.json(formattedEmergencies);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch active emergencies" });
  }
});

app.post("/user/trigger-sos", async (req, res) => {
  const { userId, locationLink } = req.body;

  if (!userId || !locationLink) {
    return res.status(400).json({ error: "Missing userId or locationLink" });
  }

  // Define email content
  const mailOptions = {
    from: '"EmergenSeek SOS" <your-email@gmail.com>',
    to: "emergency-contact@example.com", // In production, fetch this from your DB using userId
    subject: `🚨 EMERGENCY: SOS Alert from User ${userId}`,
    text: `Emergency alert triggered! \n\nUser ID: ${userId} \nLocation: ${locationLink}`,
    html: `
      <div style="font-family: Arial, sans-serif; border: 2px solid red; padding: 20px;">
        <h2 style="color: red;">🚨 Emergency SOS Alert</h2>
        <p><strong>User ID:</strong> ${userId}</p>
        <p>A user has triggered an emergency alert. You can view their live location below:</p>
        <a href="${locationLink}" style="background-color: red; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">View Location on Google Maps</a>
      </div>
    `,
  };

  try {
    await transporter.sendMail(mailOptions);
    console.log(`SOS Sent for user: ${userId}`);
    res.status(200).json({ message: "SOS Emails sent successfully!" });
  } catch (error) {
    console.error("Nodemailer Error:", error);
    res.status(500).json({ error: "Failed to send SOS email." });
  }
});

// --- SOCKET.IO REAL-TIME LOGIC ---
io.on("connection", (socket) => {
  console.log(`🔌 User Connected: ${socket.id}`);

  socket.on("join_emergency", (emergencyId) => {
    socket.join(emergencyId);
    console.log(`📡 Socket ${socket.id} joined room: ${emergencyId}`);
  });

  socket.on("update_location", (data) => {
    socket.to(data.emergencyId).emit("location_received", data);
  });

  socket.on("send_message", (data) => {
    io.to(data.emergencyId).emit("message_received", data);
  });

  socket.on("disconnect", () => {
    console.log("❌ User Disconnected");
  });
});

// --- DATABASE & SERVER START ---
if (MONGO_URI) {
  mongoose
    .connect(MONGO_URI)
    .then(() => console.log("✅ Connected to MongoDB Atlas"))
    .catch((err) => console.error("❌ MongoDB Connection Error:", err));
}

const PORT = process.env.PORT || 3000;
server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server + Socket.io listening on port ${PORT}`);
});
