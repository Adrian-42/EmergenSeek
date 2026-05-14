const mongoose = require("mongoose");

const MessageSchema = new mongoose.Schema({
  emergencyId: { type: String, required: true, index: true },
  senderId: { type: String, required: true },
  text: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
});

module.exports = mongoose.model("Message", MessageSchema);
