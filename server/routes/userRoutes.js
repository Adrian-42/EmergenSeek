const express = require("express");
const router = express.Router();
// Import your User model (adjust the path to your actual model location)
const User = require("../models/User");
const bcrypt = require("bcrypt");

// --- UPDATE EMERGENCY CONTACTS ---
// Endpoint: PUT /user/update-contacts
router.put("/update-contacts", async (req, res) => {
  const { userId, emergencyContacts } = req.body;

  try {
    const user = await User.findByIdAndUpdate(
      userId,
      { $set: { emergencyContacts: emergencyContacts } },
      { new: true },
    );

    if (!user) return res.status(404).json({ message: "User not found" });

    res.status(200).json({ message: "Contacts updated successfully", user });
  } catch (error) {
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

// --- CHANGE PASSWORD ---
// Endpoint: PUT /user/change-password
router.put("/change-password", async (req, res) => {
  const { userId, oldPassword, newPassword } = req.body;

  try {
    const user = await User.findById(userId);
    if (!user) return res.status(404).json({ message: "User not found" });

    // Verify old password
    const isMatch = await bcrypt.compare(oldPassword, user.password);
    if (!isMatch)
      return res.status(400).json({ message: "Incorrect current password" });

    // Hash new password
    const salt = await bcrypt.genSalt(10);
    user.password = await bcrypt.hash(newPassword, salt);

    await user.save();
    res.status(200).json({ message: "Password updated successfully" });
  } catch (error) {
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

module.exports = router;
