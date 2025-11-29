import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * Scheduled Cloud Function that runs daily at 12:00 AM to check for overdue tasks
 * and send push notifications to child users.
 * 
 * Schedule: Runs every day at midnight (00:00) in the timezone specified
 * To change timezone, modify the schedule: "0 0 * * *" (UTC) or use timezone parameter
 */
export const checkOverdueTasksDaily = functions.pubsub
  .schedule("0 0 * * *") // Runs at 12:00 AM UTC daily (cron format: minute hour day month dayOfWeek)
  .timeZone("UTC") // Change to your preferred timezone, e.g., "America/New_York"
  .onRun(async (context) => {
    console.log("⏰ Daily overdue task check started at:", new Date().toISOString());

    const db = admin.firestore();
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()); // Set to start of today (midnight, no time)
    
    console.log(`📅 Today's date (for comparison): ${today.toISOString().split('T')[0]}`);

    let totalNotificationsSent = 0;
    let totalTasksChecked = 0;

    try {
      // Get all parents
      const parentsSnapshot = await db.collection("Parents").get();
      console.log(`📋 Found ${parentsSnapshot.size} parents to check`);

      for (const parentDoc of parentsSnapshot.docs) {
        const parentId = parentDoc.id;
        console.log(`\n👨‍👩‍👧 Checking parent: ${parentId}`);

        // Get all children for this parent
        const childrenSnapshot = await parentDoc.ref
          .collection("Children")
          .get();

        for (const childDoc of childrenSnapshot.docs) {
          const childId = childDoc.id;
          const childData = childDoc.data();
          const fcmTokens: string[] = childData.fcmTokens || [];

          if (fcmTokens.length === 0) {
            console.log(
              `  ⏭️ Skipping child ${childId} - no FCM tokens registered`
            );
            continue;
          }

          console.log(
            `  👶 Checking child: ${childId} (${fcmTokens.length} device(s))`
          );

          // Get all tasks for this child
          // Only check tasks with status "new" (not completed, not pending, not rejected)
          const tasksSnapshot = await parentDoc.ref
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where("status", "==", "new")
            .get();

          totalTasksChecked += tasksSnapshot.size;
          console.log(
            `    📝 Found ${tasksSnapshot.size} tasks with status "new"`
          );

          const overdueTasks: Array<{
            id: string;
            taskName: string;
            dueDate: admin.firestore.Timestamp;
            daysOverdue: number;
          }> = [];

          // Check each task
          for (const taskDoc of tasksSnapshot.docs) {
            const taskData = taskDoc.data();
            const dueDate = taskData.dueDate as admin.firestore.Timestamp | null;

            if (!dueDate) {
              continue; // Skip tasks without dueDate
            }

            // Convert dueDate to Date (only date part, no time)
            const dueDateObj = dueDate.toDate();
            const dueDateOnly = new Date(
              dueDateObj.getFullYear(),
              dueDateObj.getMonth(),
              dueDateObj.getDate()
            );

            // Check if due date is today (to exclude from notifications)
            const isDueDateToday = 
              dueDateOnly.getFullYear() === today.getFullYear() &&
              dueDateOnly.getMonth() === today.getMonth() &&
              dueDateOnly.getDate() === today.getDate();

            // Debug logging
            const dueDateStr = dueDateOnly.toISOString().split('T')[0];
            const todayStr = today.toISOString().split('T')[0];

            // Only notify if task is overdue (due date is BEFORE today, not today)
            // First check: Skip if due date is today
            if (isDueDateToday) {
              console.log(
                `    ⏭️ Skipping task "${taskData.taskName}" - due date is today (${dueDateStr} == ${todayStr}, not past due)`
              );
              continue; // Skip to next task
            }

            // Second check: Only process if due date is before today
            if (dueDateOnly >= today) {
              console.log(
                `    ⏭️ Skipping task "${taskData.taskName}" - due date is today or in the future (${dueDateStr} >= ${todayStr})`
              );
              continue; // Skip to next task
            }

            // Calculate days overdue (should be at least 1 since we excluded today)
            const daysOverdue = Math.floor(
              (today.getTime() - dueDateOnly.getTime()) / (1000 * 60 * 60 * 24)
            );

            // Safety check: Ensure daysOverdue is at least 1
            if (daysOverdue < 1) {
              console.log(
                `    ⚠️ ERROR: Task "${taskData.taskName}" has daysOverdue=${daysOverdue} but should be >= 1. Skipping.`
              );
              continue; // Skip to next task
            }

            // Add to overdue tasks
            overdueTasks.push({
              id: taskDoc.id,
              taskName: taskData.taskName || "A task",
              dueDate: dueDate,
              daysOverdue: daysOverdue,
            });

            console.log(
              `    ⚠️ Overdue task found: "${taskData.taskName}" (due ${dueDateStr}, today ${todayStr}, ${daysOverdue} day(s) overdue)`
            );
          }

          // Send notifications for overdue tasks
          if (overdueTasks.length > 0) {
            console.log(
              `    📢 Sending notifications for ${overdueTasks.length} overdue task(s)`
            );

            // Send one notification per device token
            const notificationPromises = fcmTokens.map(async (token) => {
              try {
                // Create notification message
                const message: admin.messaging.Message = {
                  notification: {
                    title: "Task Overdue",
                    body:
                      overdueTasks.length === 1
                        ? `${overdueTasks[0].taskName} was due ${
                            overdueTasks[0].daysOverdue === 1
                              ? "1 day ago"
                              : `${overdueTasks[0].daysOverdue} days ago`
                          }.`
                        : `You have ${overdueTasks.length} overdue task(s).`,
                  },
                  data: {
                    type: "overdue_task",
                    taskCount: overdueTasks.length.toString(),
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                  },
                  token: token, // Send to single token
                  android: {
                    priority: "high" as const,
                    notification: {
                      channelId: "overdue_task_channel",
                      sound: "default",
                      priority: "high" as const,
                    },
                  },
                  apns: {
                    payload: {
                      aps: {
                        sound: "default",
                        badge: overdueTasks.length,
                      },
                    },
                  },
                };

                const response = await admin.messaging().send(message);
                console.log(
                  `      ✅ Notification sent to token ${token.substring(0, 20)}... - Message ID: ${response}`
                );
                return 1; // Success
              } catch (error) {
                console.error(
                  `      ❌ Error sending notification to token ${token.substring(0, 20)}...:`,
                  error
                );
                return 0; // Failure
              }
            });

            const results = await Promise.all(notificationPromises);
            totalNotificationsSent += results.reduce((sum, count) => sum + count, 0);
          }
        }
      }

      console.log(
        `\n✅ Daily check complete. Tasks checked: ${totalTasksChecked}, Notifications sent: ${totalNotificationsSent}`
      );
      return null;
    } catch (error) {
      console.error("❌ Error in daily overdue task check:", error);
      throw error;
    }
  });

/**
 * Firestore trigger that listens for task updates and sends FCM notifications
 * when a task's dueDate changes to an overdue date.
 * 
 * This ensures notifications appear even when the app is in foreground,
 * as FCM notifications can show even when the app is active.
 */
export const onTaskDueDateChanged = functions.firestore
  .document("Parents/{parentId}/Children/{childId}/Tasks/{taskId}")
  .onUpdate(async (change, context) => {
    const taskId = context.params.taskId;
    const childId = context.params.childId;
    const parentId = context.params.parentId;

    console.log(
      `📝 Task updated: ${taskId} for child ${childId} under parent ${parentId}`
    );

    const beforeData = change.before.data();
    const afterData = change.after.data();

    // Get old and new dueDate
    const oldDueDate = beforeData.dueDate as admin.firestore.Timestamp | null;
    const newDueDate = afterData.dueDate as admin.firestore.Timestamp | null;
    const status = (afterData.status || "").toString();

    // Only process if status is "new" and dueDate exists
    if (status !== "new" || !newDueDate) {
      console.log(
        `  ⏭️ Skipping - status is "${status}" (not "new") or no dueDate`
      );
      return null;
    }

    // Check if dueDate actually changed
    if (oldDueDate && oldDueDate.isEqual(newDueDate)) {
      console.log(`  ⏭️ Skipping - dueDate did not change`);
      return null;
    }

    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const dueDateObj = newDueDate.toDate();
    const dueDateOnly = new Date(
      dueDateObj.getFullYear(),
      dueDateObj.getMonth(),
      dueDateObj.getDate()
    );

    // Check if due date is today or tomorrow (for reminder notifications)
    const isDueDateToday =
      dueDateOnly.getFullYear() === today.getFullYear() &&
      dueDateOnly.getMonth() === today.getMonth() &&
      dueDateOnly.getDate() === today.getDate();
    
    const isDueDateTomorrow =
      dueDateOnly.getFullYear() === tomorrow.getFullYear() &&
      dueDateOnly.getMonth() === tomorrow.getMonth() &&
      dueDateOnly.getDate() === tomorrow.getDate();

    const taskName = afterData.taskName || "A task";
    let notificationTitle = "";
    let notificationBody = "";
    let notificationType = "";

    // Handle reminder notifications (due today or tomorrow)
    if (isDueDateToday) {
      notificationTitle = "Task Due Today";
      notificationBody = `${taskName} is due today. Don't forget to complete it!`;
      notificationType = "task_reminder_today";
      console.log(
        `  📅 Task "${taskName}" is due today - Sending reminder FCM notification`
      );
    } else if (isDueDateTomorrow) {
      notificationTitle = "Task Due Tomorrow";
      notificationBody = `${taskName} is due tomorrow. Remember to complete it!`;
      notificationType = "task_reminder_tomorrow";
      console.log(
        `  📅 Task "${taskName}" is due tomorrow - Sending reminder FCM notification`
      );
    } else if (dueDateOnly < today) {
      // Task is overdue (past due, not today or tomorrow)
      const daysOverdue = Math.floor(
        (today.getTime() - dueDateOnly.getTime()) / (1000 * 60 * 60 * 24)
      );

      if (daysOverdue < 1) {
        console.log(
          `  ⏭️ Skipping - daysOverdue is ${daysOverdue} (should be >= 1)`
        );
        return null;
      }

      const overdueText =
        daysOverdue === 1 ? "1 day ago" : `${daysOverdue} days ago`;
      notificationTitle = "Task Overdue";
      notificationBody = `${taskName} was due ${overdueText}.`;
      notificationType = "overdue_task";
      console.log(
        `  ⚠️ Task "${taskName}" is overdue! (${daysOverdue} day(s) overdue) - Sending FCM notification`
      );
    } else {
      // Task is in the future (more than 1 day away)
      console.log(
        `  ⏭️ Skipping - due date is more than 1 day in the future`
      );
      return null;
    }

    try {
      // Get child's FCM tokens
      const childDoc = await admin
        .firestore()
        .collection("Parents")
        .doc(parentId)
        .collection("Children")
        .doc(childId)
        .get();

      const childData = childDoc.data();
      const fcmTokens: string[] = childData?.fcmTokens || [];

      if (fcmTokens.length === 0) {
        console.log(`  ⏭️ No FCM tokens found for child ${childId}`);
        return null;
      }

      // Send FCM notification to all device tokens
      const notificationPromises = fcmTokens.map(async (token) => {
        try {
          const message: admin.messaging.Message = {
            notification: {
              title: notificationTitle,
              body: notificationBody,
            },
            data: {
              type: notificationType,
              taskId: taskId,
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
            token: token,
            android: {
              priority: "high" as const,
              notification: {
                channelId: notificationType.startsWith("task_reminder") 
                  ? "foreground_service_channel" 
                  : "overdue_task_channel",
                sound: "default",
                priority: "high" as const,
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                },
              },
            },
          };

          const response = await admin.messaging().send(message);
          console.log(
            `    ✅ FCM notification sent to token ${token.substring(0, 20)}... - Message ID: ${response}`
          );
          return 1;
        } catch (error) {
          console.error(
            `    ❌ Error sending FCM notification to token ${token.substring(0, 20)}...:`,
            error
          );
          return 0;
        }
      });

      const results = await Promise.all(notificationPromises);
      const successCount = results.reduce((sum, count) => sum + count, 0);

      const notificationTypeText = isDueDateToday 
        ? "reminder (due today)" 
        : isDueDateTomorrow 
        ? "reminder (due tomorrow)" 
        : "overdue";
      console.log(
        `  ✅ Sent ${successCount} FCM notification(s) for ${notificationTypeText} task "${taskName}"`
      );

      return null;
    } catch (error) {
      console.error(`  ❌ Error processing task update:`, error);
      return null; // Don't throw - we don't want to retry failed notifications
    }
  });

