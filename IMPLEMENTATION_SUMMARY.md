# Implementation Summary: Scheduled Overdue Task Notifications

## Overview

A complete system has been implemented to send push notifications at 12:00 AM daily when tasks become overdue. The system uses Firebase Cloud Functions with scheduled Pub/Sub triggers and Firebase Cloud Messaging (FCM) to deliver notifications even when the app is closed.

## Components Implemented

### 1. Firebase Cloud Function (`functions/src/index.ts`)

**Function Name:** `checkOverdueTasksDaily`

**Features:**
- Runs daily at 12:00 AM UTC (configurable)
- Checks all tasks in Firestore under `Parents/{parentId}/Children/{childId}/Tasks`
- Only checks tasks with `status == "new"` (not completed)
- Only notifies for tasks where `dueDate < today` (past due, not today)
- Sends FCM push notifications to all registered device tokens
- Notification title: "Task Overdue"
- Notification body: Task name and days overdue

**Schedule Configuration:**
- Cron: `"0 0 * * *"` (midnight daily)
- Timezone: `"UTC"` (changeable in code)

### 2. Flutter Client Updates

**Files Modified:**
- `lib/main.dart` - Updated background notification handler to support overdue task notifications
- `lib/screens/services/notification_service.dart` - Already has overdue task channel configured

**Features:**
- Background notification handler receives FCM messages when app is closed
- Notification channel `overdue_task_channel` is created on Android
- Proper notification display for both foreground and background states

### 3. Configuration Files

**Created:**
- `functions/package.json` - Node.js dependencies
- `functions/tsconfig.json` - TypeScript configuration
- `functions/.eslintrc.js` - ESLint configuration
- `functions/.gitignore` - Git ignore rules
- `functions/README.md` - Functions documentation

**Updated:**
- `firebase.json` - Added functions configuration

## How It Works

1. **Daily Check (12:00 AM UTC):**
   - Cloud Function is triggered by Pub/Sub scheduler
   - Iterates through all parents in Firestore
   - For each parent, checks all children
   - For each child, queries tasks with `status == "new"`
   - Filters tasks where `dueDate < today` (past due)

2. **Notification Sending:**
   - Retrieves FCM tokens from `Parents/{parentId}/Children/{childId}/fcmTokens`
   - Sends push notification to each registered device
   - Notification includes task name and days overdue

3. **Client Reception:**
   - FCM delivers notification to device
   - Background handler (`_firebaseMessagingBackgroundHandler`) processes notification
   - Notification is displayed even when app is closed

## Requirements Met

✅ **Scheduled mechanism at 12:00 AM** - Implemented with Pub/Sub cron trigger  
✅ **Checks all tasks** - Iterates through all parents/children/tasks  
✅ **Only notifies for overdue tasks** - Filters by `dueDate < today` and `status == "new"`  
✅ **Works when app is closed** - Uses FCM background notifications  
✅ **Firebase Cloud Functions** - Implemented with TypeScript  
✅ **FCM for notifications** - Uses Firebase Cloud Messaging  
✅ **Notification title: "Task Overdue"** - Set in Cloud Function  
✅ **Scheduled Pub/Sub triggers** - Uses `functions.pubsub.schedule()`  
✅ **Checks Firestore tasks collection** - Queries `Parents/{parentId}/Children/{childId}/Tasks`  
✅ **Only sends if status is "new"** - Filters with `.where("status", "==", "new")`  
✅ **Only sends if dueDate < today** - Date comparison logic implemented  

## Deployment Steps

1. **Install dependencies:**
   ```bash
   cd functions
   npm install
   ```

2. **Build TypeScript:**
   ```bash
   npm run build
   ```

3. **Deploy to Firebase:**
   ```bash
   firebase deploy --only functions:checkOverdueTasksDaily
   ```

See `DEPLOYMENT_GUIDE.md` for detailed instructions.

## Testing

### Test Locally:
```bash
cd functions
npm run serve
```

### Test in Production:
```bash
firebase functions:shell
checkOverdueTasksDaily()
```

### View Logs:
```bash
firebase functions:log --only checkOverdueTasksDaily
```

## Customization

### Change Schedule Time:
Edit `functions/src/index.ts`:
```typescript
.schedule("0 0 * * *") // Change cron expression
.timeZone("UTC") // Change timezone
```

### Change Notification Title:
Edit `functions/src/index.ts`, line 126:
```typescript
title: "Task Overdue", // Change this
```

## Important Notes

1. **Billing:** Cloud Functions require Firebase Blaze plan (pay-as-you-go)
2. **FCM Tokens:** Must be saved in Firestore at `Parents/{parentId}/Children/{childId}/fcmTokens` (already implemented in `notification_service.dart`)
3. **Task Status:** Only tasks with `status == "new"` are checked
4. **Due Date:** Tasks due today are excluded (only past due tasks trigger notifications)
5. **Timezone:** Currently set to UTC - change if needed for local time

## File Structure

```
Haseela.App/
├── functions/
│   ├── src/
│   │   └── index.ts          # Cloud Function code
│   ├── package.json          # Dependencies
│   ├── tsconfig.json         # TypeScript config
│   ├── .eslintrc.js          # ESLint config
│   ├── .gitignore            # Git ignore
│   └── README.md             # Functions docs
├── lib/
│   ├── main.dart             # Updated background handler
│   └── screens/
│       └── services/
│           └── notification_service.dart  # Already configured
├── firebase.json             # Updated with functions config
├── DEPLOYMENT_GUIDE.md       # Deployment instructions
└── IMPLEMENTATION_SUMMARY.md # This file
```

## Next Steps

1. Deploy the Cloud Function (see `DEPLOYMENT_GUIDE.md`)
2. Test with a task that has a past due date
3. Monitor logs to ensure function runs correctly
4. Adjust timezone if needed for your region

