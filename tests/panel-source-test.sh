#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PANEL_SOURCE=$(<"$ROOT/Panel.qml")

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
  [[ $PANEL_SOURCE == *"$1"* ]] || fail "$2"
}
assert_not_contains() {
  [[ $PANEL_SOURCE != *"$1"* ]] || fail "$2"
}

assert_contains 'glyph: broken ? "󰅖" : (running ? "󰑮" : (checks === "SUCCESS" ? "󰄬" : ""))' \
  "authored pull requests without checks do not use the pull request glyph"
assert_contains $'text: linkRow.title\n          textFormat: Text.PlainText' \
  "row titles are not forced to plain text"
assert_contains $'text: linkRow.detail\n          textFormat: Text.PlainText' \
  "row details are not forced to plain text"
assert_contains $'text: github.notificationActionStatus\n            textFormat: Text.PlainText' \
  "notification action status is not forced to plain text"
assert_contains $'return summary\n              }\n              textFormat: Text.PlainText' \
  "dashboard warning text is not forced to plain text"
assert_contains $'actionText: "Mark all read"\n            actionBusyText: "Marking…"\n            actionEnabled: github.state === "ready" && github.notifications.length > 0 && !github.marking\n            actionBusy: github.marking\n            actionRevision: github.notificationsRevision\n            actionPrepare: function() { return github.prepareMarkAllNotificationsRead() }\n            onActionTriggered: function(prepared) { github.markAllNotificationsRead(prepared) }' \
  "notification bulk action is not bound to the prepared displayed snapshot"
assert_contains 'interactive: false' \
  "the dashboard Flickable still steals presses from Mark all read"
assert_contains 'function clickMarkAll(): string' \
  "mark-all cannot be armed through omarchy-shell IPC"
assert_contains $'onActionBusyChanged: if (section.actionBusy) section.disarmAction()\n    onActionEnabledChanged: if (!section.actionEnabled) section.disarmAction()' \
  "bulk confirmation is not invalidated when notification state changes"
assert_not_contains $'onActionRevisionChanged: if (section.actionArmed) section.disarmAction()' \
  "a background refresh still cancels Confirm?"
assert_contains $'var confirmed = section.preparedAction\n          section.disarmAction()\n          section.actionTriggered(confirmed)' \
  "bulk action does not submit the originally prepared snapshot"
assert_contains $'function activateCursor() {\n    if (!selectedTarget) return\n    openRow(selectedTarget.kind, selectedTarget.row.id, selectedTarget.row.url)' \
  "opening a notification from the keyboard does not mark it read"
assert_contains $'function openRow(kind, id, url) {\n    var target = String(url || "")\n    var notificationId = String(id || "")\n    openUrl(target)\n    if (kind === "notification") github.markNotificationRead(notificationId)' \
  "opening a notification marks it before launching the URL"
assert_contains $'function markSelectedRead() {\n    if (selectedTarget && selectedTarget.kind === "notification") github.markNotificationRead(String(selectedTarget.row["id"] || selectedTarget.row.id || ""))' \
  "keyboard notification marking is blocked during refresh"
assert_contains $'function markSelectedDone() {\n    if (selectedTarget && selectedTarget.kind === "notification") github.markNotificationDone(String(selectedTarget.row["id"] || selectedTarget.row.id || ""))' \
  "keyboard Done is missing"
assert_contains $'onClicked: root.openRow(linkRow.rowKind, linkRow.notificationId || linkRow.rowId, linkRow.url)' \
  "clicking a notification does not open and mark it read"
assert_contains $'function allowedGithubUrl(url) {\n    var value = String(url || "").trim()\n    if (value === "") return ""\n    if (!/^https:\\/\\/(gist\\.)?github\\.com(\\/|$)/i.test(value)) return ""' \
  "opened links are not restricted to github.com"
assert_contains $'function openUrl(url) {\n    var value = allowedGithubUrl(url)\n    if (value === "") return' \
  "openUrl does not discard non-GitHub urls"
assert_contains $'if (github.linkBehavior === "Browser tab") Util.execArgv(["xdg-open", value])\n    else Quickshell.execDetached(["omarchy-launch-webapp", value])' \
  "the open-links setting does not choose between the browser and the web app window"

# updateEntryInline rewrites the shell.json entry whole, so a persist that does
# not carry the current settings forward silently drops every other setting.
assert_contains $'var entry = { id: root.moduleName }\n    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]' \
  "persisting a setting does not merge the entry from the current settings"
assert_contains 'root.bar.shell.updateEntryInline(root.moduleName, entry)' \
  "settings changes are not written back to shell.json"
# Dropdown writes `value` imperatively on selection, which destroys a plain
# inline binding the first time a row is picked.
assert_contains $'Binding on value { value: github.linkBehavior }' \
  "the open-links dropdown does not re-assert the persisted value"
assert_contains 'blocked: root.settingsOpen' \
  "the key catcher steals keys from the settings controls"
assert_contains 'visible: !root.settingsOpen' \
  "the dashboard stays visible behind the settings page"
assert_contains 'visible: root.settingsOpen' \
  "the settings page is always visible"
assert_contains $'pageFlip.stop()\n      settingsOpen = false' \
  "closing the panel leaves it on the settings page"
assert_contains $'id: notificationActions\n      visible: linkRow.showReadAction\n      anchors.right: parent.right\n      anchors.top: parent.top\n      anchors.bottom: parent.bottom\n      width: Style.space(linkRow.showDoneAction ? 64 : 32)' \
  "notification read target does not fill the row height at its right edge"
assert_contains $'anchors.right: notificationActions.visible ? notificationActions.left : parent.right\n      anchors.verticalCenter: parent.verticalCenter\n      anchors.leftMargin: Style.space(9)\n      anchors.rightMargin: notificationActions.visible ? 0 : Style.space(9)' \
  "notification content does not meet the full-height read target"
assert_contains 'tooltipText: "Done (D)"' \
  "notification rows have no Done action"
assert_contains $'borderSpec: Border.none()\n\n      HoverHandler {\n        onHoveredChanged: if (hovered) root.selectKey(linkRow.cursorKey)\n      }\n\n      Rectangle {\n        anchors.left: parent.left\n        anchors.top: parent.top\n        anchors.bottom: parent.bottom' \
  "notification read target does not use a left-only divider"
assert_contains $'enabled: github.markingNotificationId !== linkRow.notificationId\n          iconText: github.markingNotificationId === linkRow.notificationId && github.markingMode !== "done" ? "󰑐" : "󰄬"' \
  "notification read target does not fill its action strip"
assert_contains $'function notificationRows() {\n    var page = Math.max(0, Math.min(notificationsPage, notificationPageCount() - 1))' \
  "notifications are not paged in five-item windows"
assert_contains $'onPreviousPage: root.notificationsPage = Math.max(0, root.notificationsPage - 1)\n            onNextPage: root.notificationsPage = Math.min(root.notificationPageCount() - 1, root.notificationsPage + 1)' \
  "notification page controls do not clamp their range"
assert_contains $'model: root.notificationRows()\n            showExpansionControl: false\n            footerButtonsBordered: true\n            page: root.notificationsPage' \
  "notification pagination still shows an inactive expansion control"
assert_contains $'showReadAction: true\n      showDoneAction: true\n      showTrailingIndicator: false\n      notificationId: String(modelData["id"] || modelData.id || "")' \
  "notification rows retain an open-link indicator beside their read action"
assert_contains $'title: "ASSIGNED ISSUES"\n            count: github.assignedIssues.length\n            model: root.sectionRows(github.assignedIssues, root.issuesExpanded)\n            expanded: root.issuesExpanded\n            footerButtonsBordered: true\n            openUrl: "https://github.com/issues/assigned"' \
  "assigned-issues open control does not retain its matching border"
assert_contains 'readonly property bool showAction: section.count > 0 && section.actionText !== ""' \
  "bulk notification action disappears while data is loading"
assert_contains 'enabled: section.actionEnabled && !section.actionBusy' \
  "bulk notification action is not disabled until it is ready"
assert_contains $'text: "󰅁"\n        tooltipText: "Previous notifications"' \
  "previous notification page control is missing"
assert_contains $'text: "󰅂"\n        tooltipText: "Next notifications"' \
  "next notification page control is missing"
assert_contains $'text: (section.page + 1) + " / " + section.pageCount\n        height: previousPageButton.height\n        color: root.dim' \
  "notification page number is not vertically centered with its controls"

assert_contains $'function applyPanelWheel(event) {\n    if (!panelFlick) return false' \
  "the panel still uses Flickable's default wheel distance"
assert_contains $'panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - wheel.steps * Style.space(80)))' \
  "a mouse-wheel notch does not move about one row"
assert_contains $'ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }\n        // Must be a direct child of Flickable or Qt keeps the default\n        // 1–2px wheel distance and this handler never runs.\n        WheelHandler {\n          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad' \
  "the wheel handler is not a direct child of the panel Flickable"

assert_not_contains "OWNED REPOSITORIES" \
  "the owned repositories dashboard is still in the panel"
assert_not_contains "Filter repositories" \
  "repository search is still in the panel"

echo "panel source tests passed"
