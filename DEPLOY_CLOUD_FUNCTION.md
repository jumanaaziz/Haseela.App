# Deploy Cloud Function for Overdue Task Notifications

This guide will help you deploy the Cloud Function that sends FCM notifications when a task's `dueDate` is changed to an overdue date.

## Prerequisites

1. **Node.js** (v18 or later) - [Download here](https://nodejs.org/)
2. **Firebase CLI** - Install with: `npm install -g firebase-tools`
3. **Firebase project access** - Make sure you're logged in: `firebase login`

## Step-by-Step Deployment

### 1. Navigate to the functions directory
```bash
cd Haseela.App/functions
```

### 2. Install dependencies
```bash
npm install
```

### 3. Build TypeScript
```bash
npm run build
```

### 4. Deploy the function
```bash
firebase deploy --only functions:onTaskDueDateChanged
```

Or deploy all functions:
```bash
firebase deploy --only functions
```

## What This Function Does

The `onTaskDueDateChanged` function:
- Listens for changes to task documents in Firestore
- Detects when `dueDate` is changed to a past date (overdue)
- Only triggers if task status is "new" and due date is NOT today
- Sends FCM push notifications to the child user's devices
- Works even when the app is in foreground (FCM notifications can show in foreground)

## Testing

After deployment:
1. Open your Firebase Console → Functions
2. Change a task's `dueDate` in Firestore to yesterday
3. Check the function logs to see if it triggered
4. You should receive an FCM notification on your device

## Troubleshooting

- **"npm not found"**: Install Node.js from https://nodejs.org/
- **"firebase not found"**: Run `npm install -g firebase-tools`
- **Permission errors**: Make sure you're logged in with `firebase login`
- **Build errors**: Check that all dependencies are installed with `npm install`

## Function Logs

View function logs in Firebase Console:
- Go to Firebase Console → Functions → Logs
- Or use CLI: `firebase functions:log`

