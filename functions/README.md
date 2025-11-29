# Firebase Cloud Functions for Haseela App

This directory contains Firebase Cloud Functions for the Haseela app.

## Functions

### `checkOverdueTasksDaily`
A scheduled function that runs daily at 12:00 AM UTC to check for overdue tasks and send push notifications to child users.

**Schedule:** Runs every day at midnight (00:00) UTC
**Trigger:** Pub/Sub scheduled trigger (cron job)

## Setup

1. Install dependencies:
```bash
cd functions
npm install
```

2. Build TypeScript:
```bash
npm run build
```

3. Deploy to Firebase:
```bash
firebase deploy --only functions
```

## Configuration

To change the timezone or schedule, edit `functions/src/index.ts`:
- Modify the cron schedule: `"0 0 * * *"` (minute hour day month dayOfWeek)
- Change timezone: `.timeZone("UTC")` to your preferred timezone (e.g., `"America/New_York"`)

## Testing

Test locally using the Firebase emulator:
```bash
npm run serve
```

