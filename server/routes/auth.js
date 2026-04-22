const express = require("express");
const router = express.Router(); // Use Router instead of app
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const User = require("../models/User"); // Check this path!

// REGISTER
router.post("/register", async (req, res) => {
  try {
    const { name, email, password } = req.body; // Added name
    const hashedPassword = await bcrypt.hash(password, 10);
    const newUser = new User({ name, email, password: hashedPassword });
    await newUser.save();
    res.status(201).json({ message: "User created" });
  } catch (err) {
    res.status(500).json({ error: "Email already exists or server error" });
  }
});

// LOGIN
router.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ error: "User not found" });

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) return res.status(400).json({ error: "Invalid credentials" });

    const token = jwt.sign(
      { id: user._id },
      process.env.JWT_SECRET || "YOUR_SECRET_KEY",
      {
        expiresIn: "7d",
      },
    );
    res.json({ token, userId: user._id, email: user.email });
  } catch (err) {
    res.status(500).json({ error: "Server error" });
  }
});

module.exports = router; // REQUIRED: Export the router
