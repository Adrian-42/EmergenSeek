const mongoose = require("mongoose");

// Sub-schema for cleaner contact management
const ContactSchema = new mongoose.Schema({
  name: { type: String, required: true },
  phone: { type: String, required: true },
  email: { type: String, required: true, lowercase: true, trim: true },
});

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
    },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
    },
    password: {
      type: String,
      required: true,
    },

    // 1. Role-Based Access Control
    role: {
      type: String,
      enum: ["victim", "responder"],
      default: "victim",
    },

    phoneNumber: {
      type: String,
      default: "", // Using default empty string to avoid null issues
    },

    // 2. Emergency Status (Useful for responders to find active victims)
    isEmergencyActive: {
      type: Boolean,
      default: false,
    },

    // 3. Persistent Emergency Contacts
    emergencyContacts: [ContactSchema],

    // 4. Last Known Location (Updated via Sockets)
    lastLocation: {
      lat: { type: Number },
      lng: { type: Number },
      updatedAt: { type: Date, default: Date.now },
    },

    // 5. FCM Token (For Push Notifications when app is backgrounded)
    fcmToken: {
      type: String,
      default: null,
    },
  },
  {
    timestamps: true, // Automatically adds createdAt and updatedAt
  },
);

// Indexing for faster location-based queries
userSchema.index({ "lastLocation.lat": 1, "lastLocation.lng": 1 });

module.exports = mongoose.model("User", userSchema);
