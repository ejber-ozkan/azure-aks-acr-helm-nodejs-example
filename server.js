// server.js
const express = require("express");
const app = express();
var path = require("path");

app.get('/', (req, res) => {
    //res.send('Hello world from a Node.js app!');
    res.sendFile(path.join(__dirname + '/index.html'));
})
app.listen(3000, () => {
    console.log('Server is up on 3000');
    console.log('loading index.html');
})
