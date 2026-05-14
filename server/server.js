const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const axios = require("axios");
const cors = require("cors");
const mongoose = require("mongoose");
require("dotenv").config();
const nodemailer = require("nodemailer");

// Models
const User = require("./models/User");
const Message = require("./models/Message");

// Route Imports
const authRoutes = require("./routes/auth");
const userRoutes = require("./routes/userRoutes");

const app = express();
const server = http.createServer(app);

// --- MIDDLEWARE ---
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
app.use(express.urlencoded({ extended: true }));

// --- SOCKET.IO INITIALIZATION ---
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST", "PUT", "DELETE"],
  },
});
app.set("socketio", io);

// --- EMAIL CONFIGURATION ---
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
});

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_API_KEY;
const MONGO_URI = process.env.MONGO_URI;

// --- API ROUTES ---

// Chat History
app.get("/emergency/chat/:emergencyId", async (req, res) => {
  try {
    const messages = await Message.find({ emergencyId: req.params.emergencyId })
      .sort({ timestamp: -1 })
      .limit(50);
    res.json(messages.reverse());
  } catch (err) {
    console.error("Chat History Error:", err);
    res.status(500).json({ error: "Failed to fetch chat history" });
  }
});

// Responders List
// --- FIXED: RESPONDERS IN EMERGENCY ENDPOINT ---
app.get("/emergency/responders/:emergencyId", async (req, res) => {
  try {
    const { emergencyId } = req.params;

    // 1. Validation: Prevent CastError if the ID is malformed
    if (!mongoose.Types.ObjectId.isValid(emergencyId)) {
      console.error(`Invalid Emergency ID format: ${emergencyId}`);
      return res.status(400).json({ error: "Invalid emergency ID format" });
    }

    // 2. Get unique sender IDs from the Message collection
    const responders = await Message.distinct("senderId", {
      emergencyId: emergencyId,
    });

    if (!responders || responders.length === 0) {
      return res.json([]); // Return empty list instead of erroring
    }

    // 3. Fetch details, filtering out any potentially invalid sender IDs
    const validResponderIds = responders.filter((id) =>
      mongoose.Types.ObjectId.isValid(id),
    );

    const details = await User.find({
      _id: { $in: validResponderIds },
    }).select("name phoneNumber");

    res.json(details);
  } catch (err) {
    // This will show up in your Render "Logs" tab
    console.error("CRITICAL ROUTE ERROR:", err);
    res.status(500).json({
      error: "Failed to fetch responders",
      details: err.message,
    });
  }
});

// SOS Trigger
app.post("/trigger-sos", async (req, res) => {
  const { userId, locationLink } = req.body;
  try {
    const user = await User.findById(userId);
    if (
      !user ||
      !user.emergencyContacts ||
      user.emergencyContacts.length === 0
    ) {
      return res.status(404).json({ error: "No contacts found" });
    }
    const phoneNumbers = user.emergencyContacts
      .map((c) => c.phone)
      .filter((p) => p);
    const recipientEmails = user.emergencyContacts
      .map((c) => c.email)
      .filter((email) => email)
      .join(", ");

    if (!recipientEmails) {
      return res.status(202).json({
        message: "No emails provided. Falling back to SMS.",
        fallbackToSms: true,
        phoneNumbers: phoneNumbers,
      });
    }

    const mailOptions = {
      from: `"EmergenSeek" <${process.env.EMAIL_USER}>`,
      to: recipientEmails,
      subject: `🚨 EMERGENCY SOS - ${user.name} Needs Help!`,
      html: `<h2>Emergency Alert!</h2><p><b>${user.name}</b> is requesting immediate assistance.</p><p><b>Location:</b> <a href="${locationLink}">View on Google Maps</a></p>`,
    };
    await transporter.sendMail(mailOptions);
    res.json({ message: "SOS Emails sent successfully!" });
  } catch (err) {
    console.error("SOS Email Error:", err);
    const user = await User.findById(userId);
    const phoneNumbers = user ? user.emergencyContacts.map((c) => c.phone) : [];
    res.status(500).json({
      error: "Email failed",
      fallbackToSms: true,
      phoneNumbers: phoneNumbers,
    });
  }
});

// Google Places & Directions
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

// Active Emergencies
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

// Route Controllers
app.use("/", authRoutes);
app.use("/user", userRoutes);

// --- SOCKET.IO REAL-TIME LOGIC ---
io.on("connection", (socket) => {
  console.log(`🔌 User Connected: ${socket.id}`);

  // 1. Private (One-on-One) Chat
  socket.on("join_private_chat", (roomId) => {
    socket.join(roomId);
    console.log(`👤 Private Room Joined: ${roomId}`);
  });

  socket.on("send_private_message", async (data) => {
    const messagePayload = {
      roomId: data.roomId,
      senderId: data.senderId,
      receiverId: data.receiverId,
      text: data.text,
      timestamp: new Date(),
    };
    try {
      const newMessage = new Message(messagePayload);
      await newMessage.save();
      io.to(data.roomId).emit("message_received", messagePayload);
    } catch (e) {
      console.error("Error saving private message:", e);
    }
  });

  // 2. Emergency Room (Group) Chat
  socket.on("join_emergency", (emergencyId) => {
    socket.join(emergencyId);
    console.log(`📡 Socket ${socket.id} joined room: ${emergencyId}`);
  });

  socket.on("send_message", async (data) => {
    const messagePayload = {
      emergencyId: data.emergencyId,
      text: data.text,
      senderId: data.senderId,
      timestamp: new Date(),
    };
    try {
      const newMessage = new Message(messagePayload);
      await newMessage.save();
      io.to(data.emergencyId).emit("message_received", messagePayload);
    } catch (e) {
      console.error("Error saving message:", e);
    }
  });

  // 3. Tracking & Disconnect
  socket.on("update_location", (data) => {
    socket
      .to(data.emergencyId)
      .emit("location_received", { latitude: data.lat, longitude: data.lng });
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
