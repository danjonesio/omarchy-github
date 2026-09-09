#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE_SOURCE=$(<"$ROOT/Service.qml")

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
  [[ $SERVICE_SOURCE == *"$1"* ]] || fail "$2"
}
assert_not_contains() {
  [[ $SERVICE_SOURCE != *"$1"* ]] || fail "$2"
}

assert_not_contains 'actionWatchRepos' \
  "the service still hard-codes a two-repository Actions watch list"
assert_not_contains '--watch-repo' \
  "the service still pins Actions to specific repositories instead of the helper defaults"
assert_not_contains '--watch-owner' \
  "the service still overrides the helper account watch list"
assert_contains '"--concurrency", "6"' \
  "Actions concurrency is not passed to the helper"
assert_not_contains '--repository-scope' \
  "the dropped repository scope is still passed to the helper"
assert_not_contains 'function repositoryMode()' \
  "repositoryMode is still in the service"
assert_not_contains 'function actionMode()' \
  "actionMode is still in the service"
assert_contains 'readonly property bool alarming: !iconAlwaysUnlit && (unreadCount > 0 || failingPullRequestCount > 0 || actionCount > 0)' \
  "running Actions do not light the bar icon"

assert_contains $'function refresh(force) {\n        var forced = force === true;\n        if (!forced && isFresh()) {\n            if (actionsFetchedAt === "" && !actionsLoading && !fetchProcess.running)\n                startPhase("actions", false);\n            return ;\n        }\n        if (fetchProcess.running || markProcess.running || markQueue.length > 0) {\n            refreshQueued = true;\n            return ;\n        }' \
  "refresh and notification marking are not serialized"
assert_contains 'startPhase("inbox", true)' \
  "refresh does not load the inbox before Actions"
assert_contains $'interval: 300000\n        repeat: true\n        running: root.actionCount > 0' \
  "running Actions are not polled while live"
assert_contains $'notifications = visibleNotifications(data.notifications);\n                notificationsRevision++;' \
  "notification refreshes do not invalidate prepared confirmations"
assert_contains $'hideNotification(value);\n        enqueueMark(value, "read");\n        startQueuedMark();' \
  "single-notification marking is dropped during refresh"
assert_contains $'hideNotification(value);\n        enqueueMark(value, "done");\n        startQueuedMark();' \
  "done marking is not queued"
assert_contains 'notifications = [item].concat(notifications);' \
  "failed notification marking does not restore the hidden row"
assert_not_contains $'if (value === "" || loading || fetchProcess.running || markProcess.running)' \
  "single-notification marking is still blocked during refresh"
assert_contains 'String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"' \
  "an unrecognised open-links value does not fall back to the web app window"

assert_contains $'if (markProcess.running) {\n            notificationActionStatus = "A mark-as-read is already running.";' \
  "bulk confirmation can be prepared during refresh or marking"
assert_contains $'if (!/^\\d+$/.test(id))\n                return null;' \
  "bulk confirmation accepts invalid notification IDs"
assert_contains 'return markAllSnapshot(ids);' \
  "bulk confirmation does not capture its displayed notification IDs"
assert_contains 'return ids.join(",");' \
  "bulk confirmation still serializes through JSON.parse"
assert_contains 'var value = item["id"];' \
  "notification thread ids are read through the reserved QML id property"
assert_contains $'function markAllNotificationsRead(prepared) {\n        var confirmed = String(prepared || "");\n        if (confirmed === "" || markProcess.running)\n            return ;' \
  "bulk marking is not blocked during refresh"
assert_contains $'if (confirmed !== prepareMarkAllNotificationsRead()) {\n            notificationActionStatus = "Notifications changed. Confirm again.";' \
  "bulk marking does not verify the confirmed snapshot"
assert_contains $'var commandLine = [helperPath()];\n        for (var i = 0; i < ids.length; i++)\n            commandLine.push("--mark-notification-read", String(ids[i]));' \
  "bulk marking does not patch only the confirmed notification IDs"
assert_not_contains '--mark-all-read-before' \
  "bulk marking still uses last_read_at"
assert_contains $'function hideAllNotifications() {\n        var ids = [];\n        var hidden = copyMap(hiddenNotifications);\n        var remaining = [];\n        for (var i = 0; i < notifications.length; i++) {' \
  "bulk marking does not batch its optimistic removal"
assert_contains $'hiddenNotifications = hidden;\n            notifications = remaining;\n            notificationsRevision++;' \
  "bulk marking repeatedly updates the notification model"
assert_contains $'function restoreHiddenNotifications(ids) {\n        var values = Array.isArray(ids) ? ids : [];\n        for (var i = values.length - 1; i >= 0; i--)' \
  "failed bulk marking does not preserve notification order"
assert_contains $'markingAllNotifications = true;\n        markingAllNotificationIds = hideAllNotifications();\n        notificationActionStatus = "Marking all notifications read…";' \
  "bulk marking does not provide immediate visible feedback"
assert_contains $'if (all)\n                    root.restoreHiddenNotifications(root.markingAllNotificationIds);\n                else if (markedId !== "")' \
  "failed bulk marking does not restore its displayed notifications"
assert_contains $'root.refreshQueued = false;\n            Qt.callLater(function() { root.startPhase("inbox", false); });' \
  "notification marking does not reconcile every result with an authoritative refresh"
assert_not_contains 'root.notifications = root.notifications.filter' \
  "notification marking still hides rows using stale local data"

echo "service source tests passed"
