# Use the official Node.js image as a base image
FROM node:20 

# Set the working directory inside the container
WORKDIR /app

# Copy package.json and package-lock.json (if available)
COPY package*.json ./

# Install Angular CLI globally
RUN npm install -g @angular/cli

# Install dependencies
RUN npm install

# Copy the entire project directory into the container
COPY . .

# Build the Angular app for production
RUN ng build

CMD ["node","index.js"]



