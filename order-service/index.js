const express = require("express");
const app = express();

app.get("/", (req, res) => {
    res.json([
        { id: 1, product: "Laptop", status: "shipped" }
    ]);
});

app.listen(3003);