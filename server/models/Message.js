const mongoose = require("mongoose");

const MessageSchema = new mongoose.Schema({
  emergencyId: { type: String, index: true },
  roomId: { type: String, index: true },
  senderId: { type: String, required: true },
  senderName: { type: String }, // Add this
  receiverId: { type: String },
  text: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
});

module.exports = Message;
