const express = require("express");
const router = express.Router();
const User = require("../models/User");
const bcrypt = require("bcrypt");
const nodemailer = require("nodemailer");

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: { user: process.env.EMAIL_USER, pass: process.env.EMAIL_PASS },
});

// 1. Get User Profile
router.get("/:id", async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select("-password");
    if (!user) return res.status(404).json({ error: "User not found" });
    res.json(user);
  } catch (err) {
    res.status(400).json({ error: "Invalid User ID" });
  }
});

// 2. Update Safety Status (SOS Toggle)
router.put("/status", async (req, res) => {
  const { userId, isSafe, lastLocation } = req.body;
  try {
    const user = await User.findByIdAndUpdate(
      userId,
      { isSafe, lastLocation },
      { new: true },
    );
    if (!user) return res.status(404).json({ error: "User not found" });

    const io = req.app.get("socketio");

    if (!isSafe) {
      io.emit("new_emergency_alert", {
        userId: user._id,
        userName: user.name,
        location: lastLocation,
      });
    } else {
      io.emit("status_changed", { userId: user._id, isSafe: true });
    }
    res.json({ message: "Status updated successfully", isSafe: user.isSafe });
  } catch (err) {
    res.status(500).json({ error: "Failed to update status" });
  }
});

// 3. Update Emergency Contacts
router.put("/update-contacts", async (req, res) => {
  const { userId, emergencyContacts } = req.body;
  try {
    const user = await User.findByIdAndUpdate(
      userId,
      { $set: { emergencyContacts } },
      { new: true },
    );
    if (!user) return res.status(404).json({ message: "User not found" });
    res.status(200).json({ message: "Contacts updated successfully" });
  } catch (error) {
    res.status(500).json({ message: "Server error" });
  }
});

// 4. Change Password
router.put("/change-password", async (req, res) => {
  const { userId, oldPassword, newPassword } = req.body;

  // Check if fields are missing before processing
  if (!userId || !oldPassword || !newPassword) {
    return res.status(400).json({ message: "All fields are required" });
  }

  try {
    const user = await User.findById(userId);
    if (!user) return res.status(404).json({ message: "User not found" });

    // Compare old password
    const isMatch = await bcrypt.compare(oldPassword, user.password);
    if (!isMatch)
      return res.status(400).json({ message: "Current password is incorrect" });

    // Hash new password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);

    user.password = hashedPassword;
    await user.save();

    res.status(200).json({ message: "Password updated successfully" });
  } catch (error) {
    console.error("Hash Error:", error);
    res.status(500).json({ message: "Server error during password hashing" });
  }
});

// 5. Trigger SOS Email
router.post("/trigger-sos", async (req, res) => {
  const { userId, locationLink } = req.body;
  try {
    const user = await User.findById(userId);

    // Fix: Check if emergencyContacts exists and has length
    if (
      !user ||
      !user.emergencyContacts ||
      user.emergencyContacts.length === 0
    ) {
      return res
        .status(404)
        .json({ error: "No emergency contacts configured for this user." });
    }

    const recipientEmails = user.emergencyContacts
      .map((c) => c.email)
      .filter((e) => e != null && e !== "") // Ensure no empty strings
      .join(", ");

    if (!recipientEmails)
      return res
        .status(400)
        .json({ error: "Contacts exist but have no valid emails." });

    await transporter.sendMail({
      from: `"EmergenSeek" <${process.env.EMAIL_USER}>`,
      to: recipientEmails,
      subject: `🚨 SOS Alert: ${user.name} needs help!`,
      html: `<p><b>${user.name}</b> requested help.</p><p><a href="${locationLink}">View Location</a></p>`,
    });

    res.json({ message: "SOS Emails sent!" });
  } catch (err) {
    console.error("Email Error:", err);
    res.status(500).json({
      error: "Email provider rejected the request. Check EMAIL_PASS.",
    });
  }
});

module.exports = router;
