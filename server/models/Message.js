import mongoose from "mongoose";

const MessageSchema = new mongoose.Schema({
  emergencyId: { type: String, index: true },
  roomId: { type: String, index: true },
  senderId: { type: String, required: true },
  senderName: { type: String },
  receiverId: { type: String },
  text: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
});

const Message = mongoose.model("Message", MessageSchema);

export default Message;
