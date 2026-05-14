const mongoose = require("mongoose");

const MessageSchema = new mongoose.Schema({
  emergencyId: { type: String, index: true }, // Optional for private chats
  roomId: { type: String, index: true }, // Added for private chats
  senderId: { type: String, required: true },
  receiverId: { type: String }, // Useful for private chats
  text: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
});
module.exports = mongoose.model("Message", MessageSchema);
