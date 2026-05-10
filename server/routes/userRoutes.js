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

  // 2. Validate input presence
  if (!userId || !oldPassword || !newPassword) {
    console.error("❌ Password Change Failed: Missing fields", {
      userId: !!userId,
      old: !!oldPassword,
      new: !!newPassword,
    });
    return res
      .status(400)
      .json({
        message: "All fields (ID, old, and new password) are required.",
      });
  }

  try {
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: "User not found in database." });
    }

    // 3. Compare current password
    // This is often where the 500 happens if 'user.password' is missing or null
    if (!user.password) {
      return res
        .status(500)
        .json({ message: "User record is corrupted (no password found)." });
    }

    const isMatch = await bcrypt.compare(oldPassword, user.password);
    if (!isMatch) {
      return res
        .status(400)
        .json({ message: "The current password you entered is incorrect." });
    }

    // 4. Hash and Save
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);

    user.password = hashedPassword;
    await user.save();

    console.log(`✅ Password updated for user: ${user.name}`);
    res.status(200).json({ message: "Password updated successfully!" });
  } catch (error) {
    // 5. Catch the specific error to debug in Render logs
    console.error("🔥 Hashing/Database Error:", error.message);
    res
      .status(500)
      .json({ message: "Internal server error during hashing process." });
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
// ADD THIS: Update Personal Phone Number
router.put("/update-phone", async (req, res) => {
  const { userId, phoneNumber } = req.body;
  try {
    const user = await User.findByIdAndUpdate(
      userId,
      { $set: { phoneNumber: phoneNumber } },
      { new: true },
    );
    if (!user) return res.status(404).json({ message: "User not found" });
    res.status(200).json({ message: "Phone number updated successfully" });
  } catch (error) {
    res.status(500).json({ message: "Server error" });
  }
});

module.exports = router;
