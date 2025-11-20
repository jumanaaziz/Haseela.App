const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Cloud Function: Process Weekly Allowances
 * 
 * This function runs daily (via Cloud Scheduler) and processes
 * weekly allowances for all children whose allowance day matches today.
 * 
 * Schedule: Run daily at 00:00 UTC (or your preferred time)
 * Command to deploy: firebase deploy --only functions:processWeeklyAllowances
 */
exports.processWeeklyAllowances = functions.pubsub
  .schedule('0 0 * * *') // Run daily at midnight UTC
  .timeZone('UTC')
  .onRun(async (context) => {
    const today = new Date();
    const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const todayDayName = dayNames[today.getDay()];

    console.log(`🔄 Processing weekly allowances for ${todayDayName}`);

    try {
      // Get all parents
      const parentsSnapshot = await admin.firestore()
        .collection('Parents')
        .get();

      let processedCount = 0;
      let errorCount = 0;

      // Process each parent's children
      for (const parentDoc of parentsSnapshot.docs) {
        const parentId = parentDoc.id;
        const childrenSnapshot = await admin.firestore()
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .get();

        for (const childDoc of childrenSnapshot.docs) {
          const childId = childDoc.id;

          try {
            // Get allowance settings
            const allowanceDoc = await admin.firestore()
              .collection('Parents')
              .doc(parentId)
              .collection('Children')
              .doc(childId)
              .collection('allowanceSettings')
              .doc('settings')
              .get();

            if (!allowanceDoc.exists) {
              continue; // No allowance settings for this child
            }

            const allowanceData = allowanceDoc.data();
            const weeklyAmount = allowanceData.weeklyAmount || 0;
            const dayOfWeek = allowanceData.dayOfWeek || 'Sunday';
            const isEnabled = allowanceData.isEnabled || false;
            const lastProcessed = allowanceData.lastProcessed
              ? allowanceData.lastProcessed.toDate()
              : null;

            // Skip if not enabled or amount is invalid
            if (!isEnabled || weeklyAmount <= 0) {
              continue;
            }

            // Check if today matches the selected day
            if (dayOfWeek !== todayDayName) {
              continue;
            }

            // Check if already processed today
            if (lastProcessed) {
              const lastProcessedDate = lastProcessed;
              if (
                lastProcessedDate.getFullYear() === today.getFullYear() &&
                lastProcessedDate.getMonth() === today.getMonth() &&
                lastProcessedDate.getDate() === today.getDate()
              ) {
                console.log(`⏭️ Allowance already processed today for child ${childId}`);
                continue;
              }
            }

            // Check if last processed was more than 7 days ago (safety check)
            if (lastProcessed) {
              const daysSinceLastProcessed = Math.floor(
                (today - lastProcessed) / (1000 * 60 * 60 * 24)
              );
              if (daysSinceLastProcessed < 7) {
                console.log(`⏭️ Allowance processed ${daysSinceLastProcessed} days ago, skipping`);
                continue;
              }
            }

            // Process the allowance using a transaction
            await admin.firestore().runTransaction(async (transaction) => {
              // Get wallet document
              const walletRef = admin.firestore()
                .collection('Parents')
                .doc(parentId)
                .collection('Children')
                .doc(childId)
                .collection('Wallet')
                .doc('wallet001');

              const walletDoc = await transaction.get(walletRef);

              if (!walletDoc.exists) {
                throw new Error(`Wallet not found for child ${childId}`);
              }

              // Update wallet balances
              transaction.update(walletRef, {
                totalBalance: admin.firestore.FieldValue.increment(weeklyAmount),
                spendingBalance: admin.firestore.FieldValue.increment(weeklyAmount),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });

              // Create transaction record
              const transactionId = Date.now().toString();
              const transactionRef = admin.firestore()
                .collection('Parents')
                .doc(parentId)
                .collection('Children')
                .doc(childId)
                .collection('Transactions')
                .doc(transactionId);

              transaction.set(transactionRef, {
                id: transactionId,
                userId: childId,
                walletId: 'wallet001',
                type: 'deposit',
                category: 'weekly_allowance',
                amount: weeklyAmount,
                description: `Weekly Allowance - ${dayOfWeek}`,
                date: admin.firestore.FieldValue.serverTimestamp(),
                fromWallet: 'total',
                toWallet: 'spending',
              });

              // Update lastProcessed
              transaction.update(allowanceDoc.ref, {
                lastProcessed: admin.firestore.FieldValue.serverTimestamp(),
              });
            });

            processedCount++;
            console.log(`✅ Processed allowance for child ${childId}: ${weeklyAmount} SAR`);
          } catch (error) {
            errorCount++;
            console.error(`❌ Error processing allowance for child ${childId}:`, error);
          }
        }
      }

      console.log(`✅ Weekly allowance processing complete. Processed: ${processedCount}, Errors: ${errorCount}`);
      return null;
    } catch (error) {
      console.error('❌ Error in processWeeklyAllowances:', error);
      throw error;
    }
  });

/**
 * HTTP Function: Manual trigger for testing
 * 
 * Usage: Call this function via HTTP to manually trigger allowance processing
 * URL: https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/manualProcessAllowances
 */
exports.manualProcessAllowances = functions.https.onRequest(async (req, res) => {
  const today = new Date();
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const todayDayName = dayNames[today.getDay()];

  console.log(`🔄 Manual trigger: Processing weekly allowances for ${todayDayName}`);

  try {
    // Get all parents
    const parentsSnapshot = await admin.firestore()
      .collection('Parents')
      .get();

    let processedCount = 0;
    let errorCount = 0;

    // Process each parent's children
    for (const parentDoc of parentsSnapshot.docs) {
      const parentId = parentDoc.id;
      const childrenSnapshot = await admin.firestore()
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .get();

      for (const childDoc of childrenSnapshot.docs) {
        const childId = childDoc.id;

        try {
          // Get allowance settings
          const allowanceDoc = await admin.firestore()
            .collection('Parents')
            .doc(parentId)
            .collection('Children')
            .doc(childId)
            .collection('allowanceSettings')
            .doc('settings')
            .get();

          if (!allowanceDoc.exists) {
            continue;
          }

          const allowanceData = allowanceDoc.data();
          const weeklyAmount = allowanceData.weeklyAmount || 0;
          const dayOfWeek = allowanceData.dayOfWeek || 'Sunday';
          const isEnabled = allowanceData.isEnabled || false;
          const lastProcessed = allowanceData.lastProcessed
            ? allowanceData.lastProcessed.toDate()
            : null;

          if (!isEnabled || weeklyAmount <= 0) {
            continue;
          }

          if (dayOfWeek !== todayDayName) {
            continue;
          }

          // Check if already processed today
          if (lastProcessed) {
            const lastProcessedDate = lastProcessed;
            if (
              lastProcessedDate.getFullYear() === today.getFullYear() &&
              lastProcessedDate.getMonth() === today.getMonth() &&
              lastProcessedDate.getDate() === today.getDate()
            ) {
              continue;
            }
          }

          // Process the allowance
          await admin.firestore().runTransaction(async (transaction) => {
            const walletRef = admin.firestore()
              .collection('Parents')
              .doc(parentId)
              .collection('Children')
              .doc(childId)
              .collection('Wallet')
              .doc('wallet001');

            const walletDoc = await transaction.get(walletRef);

            if (!walletDoc.exists) {
              throw new Error(`Wallet not found for child ${childId}`);
            }

            transaction.update(walletRef, {
              totalBalance: admin.firestore.FieldValue.increment(weeklyAmount),
              spendingBalance: admin.firestore.FieldValue.increment(weeklyAmount),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const transactionId = Date.now().toString();
            const transactionRef = admin.firestore()
              .collection('Parents')
              .doc(parentId)
              .collection('Children')
              .doc(childId)
              .collection('Transactions')
              .doc(transactionId);

            transaction.set(transactionRef, {
              id: transactionId,
              userId: childId,
              walletId: 'wallet001',
              type: 'deposit',
              category: 'weekly_allowance',
              amount: weeklyAmount,
              description: `Weekly Allowance - ${dayOfWeek}`,
              date: admin.firestore.FieldValue.serverTimestamp(),
              fromWallet: 'total',
              toWallet: 'spending',
            });

            transaction.update(allowanceDoc.ref, {
              lastProcessed: admin.firestore.FieldValue.serverTimestamp(),
            });
          });

          processedCount++;
        } catch (error) {
          errorCount++;
          console.error(`❌ Error processing allowance for child ${childId}:`, error);
        }
      }
    }

    res.status(200).json({
      success: true,
      message: 'Weekly allowance processing complete',
      processed: processedCount,
      errors: errorCount,
      day: todayDayName,
    });
  } catch (error) {
    console.error('❌ Error in manualProcessAllowances:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

