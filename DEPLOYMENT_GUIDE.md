# Deployment Guide: Scheduled Overdue Task Notifications

This guide explains how to deploy the Firebase Cloud Function that sends daily push notifications for overdue tasks.

## Prerequisites

1. **Firebase CLI installed:**
   ```bash
   npm install -g firebase-tools
   ```

2. **Firebase project initialized:**
   ```bash
   firebase login
   firebase use haseela-95ea5  # or your project ID
   ```

3. **Node.js 18+ installed** (required for Cloud Functions)

## Setup Steps

### 1. Install Cloud Functions Dependencies

Navigate to the functions directory and install dependencies:

```bash
cd functions
npm install
```

### 2. Build TypeScript

Compile the TypeScript code:

```bash
npm run build
```

This will create the `lib/` directory with compiled JavaScript.

### 3. Deploy Cloud Function

Deploy the scheduled function to Firebase:

```bash
# From the project root
firebase deploy --only functions:checkOverdueTasksDaily
```

Or deploy all functions:

```bash
firebase deploy --only functions
```

### 4. Verify Deployment

Check that the function is deployed:

```bash
firebase functions:list
```

You should see `checkOverdueTasksDaily` in the list.

## Configuration

### Change Schedule Time

Edit `functions/src/index.ts`:

```typescript
.schedule("0 0 * * *") // Cron format: minute hour day month dayOfWeek
.timeZone("UTC") // Change to your timezone, e.g., "America/New_York"
```

**Cron format examples:**
- `"0 0 * * *"` - Every day at midnight (00:00)
- `"0 1 * * *"` - Every day at 1:00 AM
- `"0 0 * * 1"` - Every Monday at midnight

**Common timezones:**
- `"UTC"` - Coordinated Universal Time
- `"America/New_York"` - Eastern Time
- `"America/Los_Angeles"` - Pacific Time
- `"Europe/London"` - British Time
- `"Asia/Dubai"` - UAE Time

### Change Notification Title

Edit `functions/src/index.ts`, line 126:

```typescript
title: "Task Overdue", // Change this text
```

## Testing

### Test Locally (Emulator)

1. Start the Firebase emulator:
   ```bash
   cd functions
   npm run serve
   ```

2. The function will run on the emulator schedule.

### Test in Production

1. Manually trigger the function:
   ```bash
   firebase functions:shell
   checkOverdueTasksDaily()
   ```

2. Or wait for the scheduled time (12:00 AM UTC daily).

## Monitoring

### View Logs

```bash
firebase functions:log --only checkOverdueTasksDaily
```

### View in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Functions** → **Logs**
4. Filter by `checkOverdueTasksDaily`

## Troubleshooting

### Function Not Running

1. **Check billing:** Cloud Functions require a paid plan (Blaze plan)
2. **Check logs:** `firebase functions:log`
3. **Verify schedule:** Check cron expression in `index.ts`

### Notifications Not Received

1. **Check FCM tokens:** Verify tokens are saved in Firestore at `Parents/{parentId}/Children/{childId}/fcmTokens`
2. **Check task status:** Only tasks with `status == "new"` are checked
3. **Check due dates:** Tasks must have `dueDate < today` (not today)
4. **Check device permissions:** Ensure notification permissions are granted

### Build Errors

1. **TypeScript errors:** Run `npm run build` to see errors
2. **Missing dependencies:** Run `npm install` in `functions/` directory
3. **Node version:** Ensure Node.js 18+ is installed

## Cost Considerations

- **Free tier:** 2 million invocations/month
- **Scheduled functions:** Count as invocations
- **FCM:** Free for unlimited messages
- **Firestore reads:** ~$0.06 per 100,000 reads

For daily checks, you'll use:
- 1 function invocation per day = ~30/month
- Firestore reads depend on number of parents/children/tasks

## Security

The Cloud Function automatically has admin access to Firestore. Ensure:
- Firestore security rules are properly configured
- Only authorized users can read/write tasks
- FCM tokens are stored securely

## Rollback

If you need to rollback:

```bash
firebase functions:delete checkOverdueTasksDaily
```

Then redeploy the previous version.

