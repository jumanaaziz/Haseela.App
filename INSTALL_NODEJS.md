# Install Node.js to Deploy Cloud Functions

## Quick Installation Guide

### Step 1: Download Node.js
1. Go to: **https://nodejs.org/**
2. Download the **LTS version** (recommended, e.g., v20.x.x or v18.x.x)
3. Choose the **Windows Installer (.msi)** for your system (64-bit is most common)

### Step 2: Install Node.js
1. Run the downloaded `.msi` file
2. Click "Next" through the installation wizard
3. **Important**: Make sure to check "Add to PATH" option (usually checked by default)
4. Click "Install"
5. Wait for installation to complete
6. Click "Finish"

### Step 3: Verify Installation
1. **Close and reopen** your terminal/command prompt (important!)
2. Run these commands to verify:
   ```bash
   node --version
   npm --version
   ```
3. You should see version numbers (e.g., `v20.11.0` and `10.2.4`)

### Step 4: Install Firebase CLI
Once Node.js is installed, run:
```bash
npm install -g firebase-tools
```

### Step 5: Login to Firebase
```bash
firebase login
```
This will open a browser window for you to login with your Google account.

### Step 6: Deploy the Function
Navigate to the functions directory and deploy:
```bash
cd Haseela.App/functions
npm install
npm run build
firebase deploy --only functions:onTaskDueDateChanged
```

## Troubleshooting

- **"node is not recognized"**: 
  - Make sure you **closed and reopened** your terminal after installing Node.js
  - Restart your computer if it still doesn't work
  - Check if Node.js is in your PATH: Go to System Properties → Environment Variables

- **Installation fails**:
  - Make sure you have administrator rights
  - Try running the installer as Administrator (right-click → Run as Administrator)

## What This Does

Installing Node.js gives you:
- `node` - JavaScript runtime
- `npm` - Package manager (comes with Node.js)
- Ability to run Firebase Cloud Functions

## After Installation

Once Node.js is installed, you can deploy the Cloud Function that will send FCM notifications when task due dates change. These FCM notifications will appear even when your app is in the foreground!

