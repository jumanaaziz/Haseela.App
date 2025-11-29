# Weekly Allowance System - Implementation Guide

## Overview

This document describes the complete implementation of the weekly allowance system for the Haseela app, including Firestore integration, Flutter UI, and Cloud Functions.

## Architecture

### Firestore Structure

```
Parents
 └── {parentId}
      └── Children
           └── {childId}
                ├── allowanceSettings
                │    └── settings
                │         ├── weeklyAmount: <double>
                │         ├── dayOfWeek: <string>  // "Sunday", "Monday", etc.
                │         ├── isEnabled: <bool>
                │         └── lastProcessed: <Timestamp>
                ├── Wallet
                │    └── wallet001
                │         ├── totalBalance
                │         ├── spendingBalance
                │         └── savingBalance
                └── Transactions
                     └── {transactionId}
                          ├── type: "deposit"
                          ├── category: "weekly_allowance"
                          ├── amount: <double>
                          └── description: "Weekly Allowance - {dayOfWeek}"
```

## Components

### 1. AllowanceSettings Model (`lib/models/allowance_settings.dart`)

- **Fields:**

  - `weeklyAmount`: Double value for the weekly allowance amount
  - `dayOfWeek`: String representing the day (e.g., "Sunday", "Monday")
  - `isEnabled`: Boolean to enable/disable the allowance
  - `lastProcessed`: Optional DateTime timestamp of the last processed allowance

- **Methods:**
  - `fromFirestore()`: Converts Firestore document to model
  - `toFirestore()`: Converts model to Firestore document
  - `copyWith()`: Creates a copy with modified fields

### 2. AllowanceService (`lib/screens/services/allowance_service.dart`)

**Key Methods:**

- `saveAllowanceSettings(parentId, childId, settings)`: Saves or updates allowance settings
- `getAllowanceSettings(parentId, childId)`: Retrieves allowance settings for a child
- `deleteAllowanceSettings(parentId, childId)`: Deletes allowance settings
- `processImmediateAllowance(parentId, childId, settings)`: Processes allowance immediately if today matches the selected day
- `_processAllowancePayment(parentId, childId, settings)`: Internal method that:
  - Updates wallet balances using `FieldValue.increment()`
  - Creates a transaction record
  - Uses Firestore transactions for atomicity

### 3. SetUpWeeklyAllowanceScreen (`lib/screens/parent/setup_weekly_allowance_screen.dart`)

**Features:**

- Loads existing allowance settings from Firestore on init
- Allows parent to select one or multiple children
- Shows existing allowance information for each child
- Bottom sheet for entering allowance amount, day, and enable/disable
- Saves settings to Firestore
- Processes immediate allowance if today matches selected day
- Shows loading states and success/error messages

**User Flow:**

1. Parent opens the screen
2. Screen loads existing allowances for all children
3. Parent selects children (checkboxes)
4. Parent taps "Continue" button
5. Bottom sheet appears with allowance settings form
6. Parent enters amount, selects day, toggles enable/disable
7. Parent taps "Save Allowance"
8. Settings are saved to Firestore
9. If today matches selected day, allowance is processed immediately
10. Success toast appears and screen closes

### 4. Cloud Function (`functions/index.js`)

**Scheduled Function: `processWeeklyAllowances`**

- Runs daily at midnight UTC (configurable)
- Checks all children under all parents
- Processes allowances where:
  - `isEnabled == true`
  - `dayOfWeek` matches today
  - `lastProcessed` is older than 7 days or null
  - `weeklyAmount > 0`

**HTTP Function: `manualProcessAllowances`**

- Can be called manually for testing
- Same logic as scheduled function
- Returns JSON with processing results

## Deployment

### 1. Deploy Cloud Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

### 2. Configure Cloud Scheduler (Optional)

The scheduled function uses Pub/Sub. To customize the schedule:

1. Go to Firebase Console → Functions
2. Find `processWeeklyAllowances`
3. Edit the schedule (default: daily at midnight UTC)

Or update the schedule in `functions/index.js`:

```javascript
.schedule('0 0 * * *') // Daily at midnight UTC
// Change to your preferred schedule
```

### 3. Test the System

**Test Immediate Allowance:**

1. Set up allowance for a child with today's day
2. Save the settings
3. Check the child's wallet - balance should increase immediately
4. Check Transactions collection - new transaction should appear

**Test Weekly Processing:**

1. Set up allowance for a child with a future day
2. Save the settings
3. Wait for that day OR manually trigger the function:
   ```bash
   # Call the HTTP function
   curl https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/manualProcessAllowances
   ```

## Edge Cases Handled

1. **Already Processed Today**: Checks `lastProcessed` date to prevent duplicate processing
2. **Invalid Amount**: Validates amount > 0 before saving
3. **No Children Selected**: Shows error message
4. **Wallet Not Found**: Throws error with clear message
5. **Disabled Allowance**: Skips processing if `isEnabled == false`
6. **Transaction Atomicity**: Uses Firestore transactions to ensure wallet and transaction updates happen together

## Testing Scenarios

### Scenario 1: Immediate Allowance (Today Matches)

1. Today is Sunday
2. Parent sets allowance for Sunday
3. Saves settings
4. **Expected**: Allowance is processed immediately, wallet balance increases, transaction created

### Scenario 2: Future Allowance

1. Today is Monday
2. Parent sets allowance for Friday
3. Saves settings
4. **Expected**: Settings saved, no immediate processing
5. On Friday, Cloud Function processes the allowance

### Scenario 3: Weekly Cycle

1. Parent sets allowance for Sunday, 50 SAR
2. Cloud Function runs on Sunday
3. **Expected**: 50 SAR added to wallet, transaction created, `lastProcessed` updated
4. Cloud Function runs again on Sunday (next week)
5. **Expected**: Another 50 SAR added, new transaction created

### Scenario 4: Disable Allowance

1. Parent disables allowance (toggle off)
2. Cloud Function runs on the selected day
3. **Expected**: No processing, allowance skipped

### Scenario 5: Delete Allowance

1. Parent deletes allowance for a child
2. **Expected**: `allowanceSettings` document is deleted
3. Cloud Function skips this child

## Error Handling

- **Firestore Errors**: Caught and logged, user sees error message
- **Validation Errors**: Amount validation, empty fields checked before saving
- **Network Errors**: Handled with try-catch, user sees error message
- **Transaction Failures**: Rolled back automatically by Firestore

## Security Considerations

- All operations require authenticated parent user
- Firestore Security Rules should restrict access:
  ```javascript
  match /Parents/{parentId}/Children/{childId}/allowanceSettings/{document=**} {
    allow read, write: if request.auth != null && request.auth.uid == parentId;
  }
  ```

## Future Enhancements

- Allow different amounts for different children
- Allow custom schedules (bi-weekly, monthly)
- Notification when allowance is processed
- Allowance history/analytics
- Parent approval before processing

## Support

For issues or questions:

1. Check Firestore console for data structure
2. Check Cloud Functions logs in Firebase Console
3. Verify Cloud Scheduler is enabled
4. Test with manual HTTP function trigger
