const express = require("express");
const router = express.Router();
const User = require("../models/User");
const bcrypt = require("bcrypt");
const nodemailer = require("nodemailer");
const { Resend } = require("resend");
const resend = new Resend(process.env.RESEND_API_KEY);

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

  if (!userId || !oldPassword || !newPassword) {
    return res.status(400).json({ message: "All fields are required." });
  }

  try {
    const user = await User.findById(userId);
    if (!user) return res.status(404).json({ message: "User not found." });

    const isMatch = await bcrypt.compare(oldPassword, user.password);
    if (!isMatch)
      return res.status(400).json({ message: "Incorrect current password." });

    const salt = await bcrypt.genSalt(10);
    user.password = await bcrypt.hash(newPassword, salt);

    // FIX: Use validateModifiedOnly so it doesn't complain about
    // missing 'name' in emergency contacts while we are only saving the password.
    await user.save({ validateModifiedOnly: true });

    res.status(200).json({ message: "Password updated successfully!" });
  } catch (error) {
    console.error("🔥 Hashing/Database Error:", error.message);
    res.status(500).json({ message: error.message });
  }
});

// 5. Trigger SOS Email
router.post("/trigger-sos", async (req, res) => {
  const { userId, locationLink } = req.body;
  console.log("-----------------------------------------");
  console.log("📩 SOS Request Received for ID:", userId);

  try {
    const user = await User.findById(userId);
    if (!user) {
      console.error("❌ ERROR: User not found.");
      return res.status(404).json({ error: "User not found." });
    }

    console.log(`👤 User Found: ${user.name}`);

    if (!user.emergencyContacts || user.emergencyContacts.length === 0) {
      console.warn("⚠️ SOS STOPPED: No contacts found.");
      return res.status(404).json({ error: "No contacts configured." });
    }

    const recipientEmails = user.emergencyContacts
      .map((c) => c.email)
      .filter((e) => e != null && e !== "");

    if (recipientEmails.length === 0) {
      return res.status(400).json({ error: "No valid emails." });
    }

    console.log(`📧 Sending via Resend to: ${recipientEmails}`);

    // Sending via Resend API (HTTP instead of SMTP)
    const { data, error } = await resend.emails.send({
      from: "EmergenSeek emergenseek.globalcity.sti.edu.ph", // Change to your verified domain later
      to: recipientEmails,
      subject: `🚨 SOS Alert: ${user.name} needs help!`,
      html: `
        <div style="font-family: sans-serif; padding: 20px; border: 2px solid red; border-radius: 10px;">
          <h2 style="color: red;">🚨 EMERGENCY SOS ALERT</h2>
          <p><b>${user.name}</b> has triggered an SOS alert and needs assistance.</p>
          <p><b>Last Known Location:</b></p>
          <div style="margin-top: 20px;">
            <a href="${locationLink}" style="background: red; color: white; padding: 12px 25px; text-decoration: none; border-radius: 5px; font-weight: bold;">
              View on Google Maps
            </a>
          </div>
          <p style="margin-top: 20px; font-size: 12px; color: #666;">
            This alert was sent via EmergenSeek Mobile App.
          </p>
        </div>
      `,
    });

    if (error) {
      console.error("🔥 Resend API Error:", error);
      return res.status(500).json({ error: "Resend failed", details: error });
    }

    console.log("✅ SOS Emails successfully sent via Resend!");
    console.log("📬 Resend ID:", data.id);
    console.log("-----------------------------------------");
    res.json({ message: "SOS Emails sent!", id: data.id });
  } catch (err) {
    console.error("🔥 SOS FATAL ERROR:", err.message);
    res
      .status(500)
      .json({ error: "Internal server error", details: err.message });
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
