const express = require("express");
const router = express.Router();
const User = require("../models/User");
const bcrypt = require("bcrypt");
const nodemailer = require("nodemailer");

// Configure your nodemailer transporter
// Note: Use an App Password if using Gmail, not your primary password.
// Configure your nodemailer transporter
const transporter = nodemailer.createTransport({
  host: "smtp.gmail.com",
  port: 465,
  secure: true, // Use SSL
  auth: {
    user: "emergenseek000@gmail.com",
    pass: process.env.EMAIL_PASSWORD,
  },
  // ADD THIS BLOCK TO FIX ENETUNREACH
  tls: {
    rejectUnauthorized: false, // Helps with some cloud network restrictions
  },
  connectionTimeout: 10000, // 10 seconds
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
        phoneNumber: user.phoneNumber,
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

    await user.save({ validateModifiedOnly: true });

    res.status(200).json({ message: "Password updated successfully!" });
  } catch (error) {
    console.error("🔥 Hashing/Database Error:", error.message);
    res.status(500).json({ message: error.message });
  }
});

// 5. Update Personal Phone Number
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

// 6. Trigger SOS Email
router.post("/trigger-sos", async (req, res) => {
  const { userId, locationLink } = req.body;

  if (!userId || !locationLink) {
    return res.status(400).json({ error: "Missing userId or locationLink" });
  }

  try {
    // Fetch user and their emergency contacts
    const user = await User.findById(userId);

    if (!user) {
      return res.status(404).json({ error: "User not found" });
    }

    if (!user.emergencyContacts || user.emergencyContacts.length === 0) {
      return res
        .status(400)
        .json({ error: "User has no emergency contacts saved." });
    }

    // Map through the contacts to get all email addresses
    const recipientList = user.emergencyContacts.map((c) => c.email).join(", ");

    const mailOptions = {
      from: '"EmergenSeek SOS" <emergenseek000@gmail.com>',
      to: recipientList,
      subject: `🚨 EMERGENCY: SOS Alert from ${user.name}`,
      text: `Emergency alert triggered! \n\nUser: ${user.name} \nPhone: ${user.phoneNumber} \nLocation: ${locationLink}`,
      html: `
        <div style="font-family: Arial, sans-serif; border: 2px solid red; padding: 20px; border-radius: 10px;">
          <h2 style="color: red; text-align: center;">🚨 Emergency SOS Alert</h2>
          <p>This is an automated emergency message from <strong>EmergenSeek</strong>.</p>
          <hr />
          <p><strong>User:</strong> ${user.name}</p>
          <p><strong>Phone:</strong> ${user.phoneNumber || "Not provided"}</p>
          <p><strong>Status:</strong> Triggered SOS Alert</p>
          <p>The user is requesting help. You can view their current location by clicking the button below:</p>
          <div style="text-align: center; margin: 30px 0;">
            <a href="${locationLink}" style="background-color: red; color: white; padding: 15px 25px; text-decoration: none; border-radius: 5px; font-weight: bold; font-size: 16px;">View Location on Maps</a>
          </div>
          <p style="font-size: 12px; color: #555;">If the button doesn't work, copy and paste this link: ${locationLink}</p>
        </div>
      `,
    };

    await transporter.sendMail(mailOptions);
    console.log(`SOS Email sent to: ${recipientList}`);
    res.status(200).json({ message: "SOS Emails sent successfully!" });
  } catch (error) {
    console.error("Nodemailer/Database Error:", error);
    res.status(500).json({ error: "Failed to send SOS email." });
  }
});

module.exports = router;
