const express = require('express');
const path = require('path');

const app = express();

// Serve static files from the 'dist' directory
app.use(express.static(path.join(__dirname, 'dist/my-app/browser')));

// Serve the index.html file for any unknown routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'dist/my-app/browser/index.html'));
});

// Start the server on port 80
const port = process.env.PORT || 80;
app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});

