const express = require("express");


const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");

require("dotenv").config();

const app = express();

// ================= CONFIG =================

const PORT = process.env.PORT || 3003;

// ================= MIDDLEWARE =================
app.use(express.json());
app.use(cors());
app.use(helmet());
app.use(morgan("dev"));

// ================= APISIX AUTH MIDDLEWARE =================

const apisixAuthMiddleware = (req, res, next) => {
    const userId = req.headers["x-user-id"];
    const userEmail = req.headers["x-user-email"];

    if (!userId || !userEmail) {
        return res.status(401).json({ error: "Unauthorized access via Gateway ❌" });
    }

    // ইউজার ইনফো রিকোয়েস্ট অবজেক্টে অ্যাটাচ করে দেওয়া হলো
    req.user = {
        id: userId,
        email: userEmail
    };
    
    next();
};

// ================= DATA =================
let products = [
    { id: 1, name: "Laptop", price: 50000 },
    { id: 2, name: "Phone", price: 20000 }
];

// ================= ROUTES =================

// Public route
app.get("/", (req, res) => {
    res.send("Product Service is running 🚀");
});

app.get("/products", (req, res) => {
    res.json(products);
});

// 🔐 Protected: only logged-in user can add product
app.post("/products", apisixAuthMiddleware, (req, res) => {
    const { name, price } = req.body;

    if (!name || !price) {
        return res.status(400).json({ error: "Name & price required" });
    }

    const newProduct = {
        id: products.length + 1,
        name,
        price
    };

    products.push(newProduct);

    res.status(201).json({
        message: "Product added successfully ✅",
        product: newProduct,
        createdBy: req.user.email 
    });
});

// 🔐 Protected: Buy product
app.post("/buy/:id", apisixAuthMiddleware, (req, res) => {
    const productId = parseInt(req.params.id);

    const product = products.find(p => p.id === productId);

    if (!product) {
        return res.status(404).json({ error: "Product not found ❌" });
    }

    res.json({
        message: "Product purchased successfully 🛒",
        product,
        buyer: req.user.email 
    });
});

// ================= START =================
app.listen(PORT, () => {
    console.log(`Product Service running on port ${PORT} 🚀`);
});