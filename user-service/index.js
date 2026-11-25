const express = require("express");
const mongoose = require("mongoose");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
require("dotenv").config();

const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");

const app = express();

// ================= CONFIG =================
const PORT = process.env.PORT || 3002;

if (!process.env.JWT_SECRET) {
    console.error("❌ JWT_SECRET is not defined in .env");
    process.exit(1);
}

const JWT_SECRET = process.env.JWT_SECRET;

// ================= MIDDLEWARE =================
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// CORS - সব এন্ডপয়েন্টের জন্য
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    exposedHeaders: ['X-User-Id', 'X-User-Email', 'X-User-Name', 'X-User-Role']
}));

app.use(helmet({
    crossOriginResourcePolicy: { policy: "cross-origin" },
    crossOriginEmbedderPolicy: false // CORS এর সাথে কনফ্লিক্ট এড়াতে
}));

app.use(morgan("dev"));

// ================= DATABASE =================
mongoose.connect(process.env.MONGO_URI)
.then(() => console.log("✅ MongoDB Connected"))
.catch(err => {
    console.error("❌ MongoDB connection failed:", err);
    process.exit(1);
});

// ================= USER MODEL =================
const userSchema = new mongoose.Schema({
    name: { type: String, required: true },
    email: { type: String, unique: true, required: true },
    password: { type: String, required: true },
    isActive: { type: Boolean, default: true },
    role: { type: String, default: 'user' }
}, { timestamps: true });

const User = mongoose.model("User", userSchema);

// ================= HEALTH =================
app.get("/auth/health", (req, res) => {
    res.json({ 
        status: "OK", 
        service: "user-service",
        timestamp: new Date().toISOString()
    });
});

// ================= SIGNUP =================
app.post("/auth/signup", async (req, res) => {
    try {
        const { name, email, password } = req.body;

        if (!name || !email || !password) {
            return res.status(400).json({ 
                success: false,
                error: "Missing fields" 
            });
        }

        const emailLower = email.toLowerCase();

        const exists = await User.findOne({ email: emailLower });
        if (exists) {
            return res.status(400).json({ 
                success: false,
                error: "User already exists" 
            });
        }

        if (password.length < 6) {
            return res.status(400).json({ 
                success: false,
                error: "Password too weak (min 6 characters)" 
            });
        }

        const hashedPassword = await bcrypt.hash(password, 10);

        const user = new User({
            name,
            email: emailLower,
            password: hashedPassword,
            role: 'user'
        });

        await user.save();

        res.status(201).json({
            success: true,
            message: "User registered successfully ✅",
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                role: user.role
            }
        });

    } catch (err) {
        console.error("❌ Signup error:", err);
        res.status(500).json({ 
            success: false,
            error: "Internal server error" 
        });
    }
});

// ================= LOGIN =================
app.post("/auth/login", async (req, res) => {
    try {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({ 
                success: false,
                error: "Missing credentials" 
            });
        }

        const emailLower = email.toLowerCase();

        const user = await User.findOne({ email: emailLower });
        if (!user) {
            return res.status(401).json({ 
                success: false,
                error: "Invalid credentials" 
            });
        }

        if (!user.isActive) {
            return res.status(403).json({
                success: false,
                error: "Account is deactivated"
            });
        }

        const isMatch = await bcrypt.compare(password, user.password);
        if (!isMatch) {
            return res.status(401).json({ 
                success: false,
                error: "Invalid credentials" 
            });
        }

        const token = jwt.sign(
            {
                id: user._id.toString(),
                email: user.email,
                name: user.name,
                role: user.role
            },
            JWT_SECRET,
            { expiresIn: "1d" }
        );

        res.json({
            success: true,
            message: "Login successful ✅",
            token,
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                role: user.role
            }
        });

    } catch (err) {
        console.error("❌ Login error:", err);
        res.status(500).json({ 
            success: false,
            error: "Internal server error" 
        });
    }
});

// ================= AUTH MIDDLEWARE =================
const authMiddleware = (req, res, next) => {
    console.log('🔍 Auth Middleware - Headers:', {
        'authorization': req.headers.authorization ? 'Present' : 'Missing'
    });

    const authHeader = req.headers.authorization;

    if (!authHeader) {
        console.log('❌ No Authorization header');
        return res.status(401).json({ 
            success: false,
            error: "No token provided" 
        });
    }

    const parts = authHeader.split(" ");

    if (parts.length !== 2 || parts[0] !== "Bearer") {
        console.log('❌ Invalid token format');
        return res.status(401).json({ 
            success: false,
            error: "Invalid token format" 
        });
    }

    const token = parts[1];

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        console.log('✅ Token verified for user:', decoded.email);
        req.user = decoded;
        next();
    } catch (err) {
        console.log('❌ Token verification failed:', err.message);
        return res.status(401).json({ 
            success: false,
            error: "Invalid or expired token" 
        });
    }
};

// ================= PROFILE (Protected) =================
app.get("/auth/profile", authMiddleware, (req, res) => {
    res.json({
        success: true,
        message: "Protected data 🔐",
        user: req.user
    });
});

// ================= ⭐ FORWARD AUTH VERIFICATION FOR APISIX =================
app.all("/auth/verify", async (req, res) => {
    console.log('🔄 Verification request received');
    console.log('📋 Method:', req.method);
    
    // OPTIONS প্রিফ্লাইট হ্যান্ডেল
    if (req.method === 'OPTIONS') {
        return res.status(200).send();
    }

    try {
        const authHeader = req.headers.authorization;
        
        if (!authHeader) {
            console.log('❌ No Authorization header');
            return res.status(401).json({
                error: "Unauthorized",
                message: "Authorization header missing"
            });
        }

        const parts = authHeader.split(" ");
        if (parts.length !== 2 || parts[0] !== "Bearer") {
            console.log('❌ Invalid token format');
            return res.status(401).json({
                error: "Unauthorized",
                message: "Invalid token format"
            });
        }

        const token = parts[1];
        
        // টোকেন ভেরিফাই
        const decoded = jwt.verify(token, JWT_SECRET);
        console.log('✅ Token verified:', decoded.email);

        // ডাটাবেসে ইউজার চেক
        const user = await User.findById(decoded.id);
        if (!user) {
            console.log('❌ User not found');
            return res.status(403).json({
                error: "Forbidden",
                message: "User not found"
            });
        }

        if (!user.isActive) {
            console.log('❌ User is inactive');
            return res.status(403).json({
                error: "Forbidden",
                message: "User account is inactive"
            });
        }

        // ⭐ APISIX-এর জন্য হেডার সেট
        res.setHeader("X-User-Id", user._id.toString());
        res.setHeader("X-User-Email", user.email);
        res.setHeader("X-User-Name", encodeURIComponent(user.name));
        res.setHeader("X-User-Role", user.role);
        
        // CORS হেডার
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
        res.setHeader("Access-Control-Expose-Headers", "X-User-Id, X-User-Email, X-User-Name, X-User-Role");

        console.log('✅ Verification successful for:', user.email);
        
        // 200 OK রিটার্ন
        return res.status(200).json({
            status: "success",
            user: {
                id: user._id,
                email: user.email,
                name: user.name,
                role: user.role
            }
        });

    } catch (error) {
        console.error('❌ Verification error:', error.message);
        
        if (error.name === 'JsonWebTokenError') {
            return res.status(401).json({
                error: "Unauthorized",
                message: "Invalid token"
            });
        }
        
        if (error.name === 'TokenExpiredError') {
            return res.status(401).json({
                error: "Unauthorized",
                message: "Token expired"
            });
        }

        return res.status(500).json({
            error: "Internal Server Error",
            message: error.message
        });
    }
});

// ================= ব্যাকআপ VERIFY (ঐচ্ছিক) =================
app.all("/verify", async (req, res) => {
    console.log('🔄 Backup verify endpoint called');
    req.url = '/auth/verify';
    app.handle(req, res);
});

// ================= START =================
const server = app.listen(PORT, () => {
    console.log(`\n🚀 User Service running on port ${PORT}`);
    console.log(`📌 Health: http://localhost:${PORT}/auth/health`);
    console.log(`📌 Verify: http://localhost:${PORT}/auth/verify`);
    console.log(`📌 Login: http://localhost:${PORT}/auth/login`);
    console.log(`📌 Signup: http://localhost:${PORT}/auth/signup`);
    console.log(`📌 Profile: http://localhost:${PORT}/auth/profile\n`);
});

// ================= GRACEFUL SHUTDOWN =================
process.on('SIGTERM', () => {
    console.log('SIGTERM signal received: closing HTTP server');
    server.close(() => {
        console.log('HTTP server closed');
        mongoose.connection.close(false, () => {
            console.log('MongoDB connection closed');
            process.exit(0);
        });
    });
});

process.on('SIGINT', () => {
    console.log('SIGINT signal received: closing HTTP server');
    server.close(() => {
        console.log('HTTP server closed');
        mongoose.connection.close(false, () => {
            console.log('MongoDB connection closed');
            process.exit(0);
        });
    });
});

process.on('unhandledRejection', (err) => {
    console.error('❌ Unhandled Rejection:', err);
});

process.on('uncaughtException', (err) => {
    console.error('❌ Uncaught Exception:', err);
    // উৎপাদনে এখানে সার্ভিস রিস্টার্ট করার লজিক দিন
});