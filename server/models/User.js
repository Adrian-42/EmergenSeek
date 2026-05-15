import mongoose from "mongoose"; // 1. Use import instead of require

// Sub-schema for cleaner contact management
const ContactSchema = new mongoose.Schema({
  name: { type: String, required: true },
  phone: { type: String, required: true },
  email: { type: String, required: true, lowercase: true, trim: true },
});

const userSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
    },
    password: { type: String, required: true },
    role: { type: String, enum: ["victim", "responder"], default: "victim" },
    phoneNumber: { type: String, default: "" },
    isEmergencyActive: { type: Boolean, default: false },
    emergencyContacts: [ContactSchema],
    lastLocation: {
      lat: { type: Number },
      lng: { type: Number },
      updatedAt: { type: Date, default: Date.now },
    },
    fcmToken: { type: String, default: null },
  },
  { timestamps: true },
);

userSchema.index({ "lastLocation.lat": 1, "lastLocation.lng": 1 });

const User = mongoose.model("User", userSchema);

export default User;
