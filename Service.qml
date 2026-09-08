import QtQuick
import Quickshell
import Quickshell.Io

// GitHub dashboard data service. The helper owns API pagination and aggregation;
// this item schedules it and exposes one stable, defensive model to the panel.
Item {
    id: root

    property var settings: ({
    })
    property bool loading: false
    property string state: "loading"
    property string message: "Loading GitHub…"
    property string login: ""
    property string fetchedAt: ""
    property string actionsFetchedAt: ""
    property var notifications: []
    property int notificationsRevision: 0
    property var reviewRequests: []
    property var assignedIssues: []
    property var myPullRequests: []
    property int myPullRequestsTotal: 0
    property var actions: []
    property var failedActions: []
    property var repositories: []
    property var warnings: []
    property var rateLimit: null
    property string _stdout: ""
    property string _stderr: ""
    property bool refreshQueued: false
    property bool inboxLoading: false
    property bool actionsLoading: false
    property string fetchPhase: "inbox"
    property bool followUpActions: true
    property string markingMode: "read"
    property string markingNotificationId: ""
    property bool markingAllNotifications: false
    property var markingAllNotificationIds: []
    property string notificationActionStatus: ""
    property string _markStdout: ""
    property string _markStderr: ""
    // Thread IDs waiting for PATCH after GitHub confirmed them locally. An
    // in-flight refresh must not restore these rows, or the bar stays lit until
    // the next poll even though the user already opened or marked the thread.
    property var hiddenNotifications: ({})
    property var markQueue: []
    // Single-thread and bulk marking share one process, so the panel gates every
    // entry point on this rather than on whichever flag a given call happens to
    // set. A caller added later inherits the guard instead of having to know.
    readonly property bool marking: markProcess.running
    readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 900, 60, 3600)
    readonly property int unreadCount: notifications.length
    readonly property int actionCount: actions.length
    // A broken check on your own pull request is the kind of thing the bar icon
    // exists to surface, so it counts toward the alarming state. Drafts are
    // excluded: a red check on work you have not offered up yet is expected,
    // and it would leave the icon permanently lit.
    readonly property int failingPullRequestCount: myPullRequests.filter(function(item) {
        return !item.draft && root.isBrokenCheck(item.checks);
    }).length
    readonly property bool iconAlwaysUnlit: boolSetting("iconAlwaysUnlit", false)
    // An unrecognised value falls back to the web app window rather than the
    // browser, so a stale entry cannot silently revert the default behaviour.
    readonly property string linkBehavior: String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"
    // Unread mail, a broken check on your own PR, or a watch-list run kicking
    // off. Assigned issues stay in the panel without lighting the bar.
    readonly property bool alarming: !iconAlwaysUnlit && (unreadCount > 0 || failingPullRequestCount > 0 || actionCount > 0)

    // StatusCheckRollup groupings live here so the alarming count, the row label
    // and the row glyph cannot drift apart when a state is reclassified.
    function isBrokenCheck(checks) {
        var value = String(checks || "");
        return value === "FAILURE" || value === "ERROR";
    }

    function isRunningCheck(checks) {
        var value = String(checks || "");
        return value === "PENDING" || value === "EXPECTED";
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function intSetting(name, fallback, minimum, maximum) {
        var value = parseInt(String(setting(name, fallback)), 10);
        if (!isFinite(value))
            value = fallback;

        return Math.max(minimum, Math.min(maximum, value));
    }

    function boolSetting(name, fallback) {
        var value = setting(name, fallback);
        if (value === true || value === false)
            return value;

        var text = String(value).toLowerCase();
        return text === "true" || text === "yes" || text === "on" || text === "1";
    }

    function helperPath() {
        return decodeURIComponent(Qt.resolvedUrl("omarchy-github-fetch").toString().replace(/^file:\/\//, ""));
    }

    function cachePath() {
        var xdg = String(Quickshell.env("XDG_CACHE_HOME") || "");
        var home = String(Quickshell.env("HOME") || "");
        var dir = xdg !== "" ? xdg : (home + "/.cache");
        return dir + "/omarchy-github/state.json";
    }

    function isFresh() {
        var at = String(fetchedAt || "");
        if (at === "")
            return false;
        var t = Date.parse(at);
        if (!isFinite(t))
            return false;
        return (Date.now() - t) < 60000;
    }

    readonly property var actionWatchRepos: ["omacom/omarchy", "NetCask-Labs/NetCask-commercial"]

    function command(phase) {
        var p = phase || "all";
        var cmd = [helperPath(), "--phase", p, "--cache-file", cachePath(), "--concurrency", "6"];
        for (var i = 0; i < actionWatchRepos.length; i++)
            cmd.push("--watch-repo", actionWatchRepos[i]);
        return cmd;
    }

    function copyMap(value) {
        var copy = {};
        var source = value || {};
        for (var key in source)
            copy[key] = source[key];
        return copy;
    }

    // QML reserves `.id` on objects. JSON notification thread ids must be read
    // with bracket notation or every bulk snapshot looks empty.
    function threadId(item) {
        if (!item)
            return "";
        var value = item["id"];
        return value === undefined || value === null ? "" : String(value);
    }

    function hideNotification(id) {
        var value = String(id || "");
        if (value === "")
            return ;

        var hidden = copyMap(hiddenNotifications);
        var next = [];
        var found = false;
        for (var i = 0; i < notifications.length; i++) {
            var item = notifications[i];
            if (threadId(item) === value) {
                hidden[value] = item;
                found = true;
            } else {
                next.push(item);
            }
        }
        if (!found && hidden[value] === undefined)
            hidden[value] = { "id": value };

        hiddenNotifications = hidden;
        if (found) {
            notifications = next;
            notificationsRevision++;
        }
    }

    function restoreHiddenNotification(id) {
        var value = String(id || "");
        var item = hiddenNotifications[value];
        var hidden = copyMap(hiddenNotifications);
        delete hidden[value];
        hiddenNotifications = hidden;
        if (!item)
            return ;

        for (var i = 0; i < notifications.length; i++) {
            if (threadId(notifications[i]) === value)
                return ;
        }
        notifications = [item].concat(notifications);
        notificationsRevision++;
    }

    function hideAllNotifications() {
        var ids = [];
        var hidden = copyMap(hiddenNotifications);
        var remaining = [];
        for (var i = 0; i < notifications.length; i++) {
            var item = notifications[i];
            var id = threadId(item);
            if (id !== "") {
                ids.push(id);
                hidden[id] = item;
            } else {
                remaining.push(item);
            }
        }
        if (ids.length > 0) {
            hiddenNotifications = hidden;
            notifications = remaining;
            notificationsRevision++;
        }
        return ids;
    }

    function restoreHiddenNotifications(ids) {
        var values = Array.isArray(ids) ? ids : [];
        for (var i = values.length - 1; i >= 0; i--)
            restoreHiddenNotification(values[i]);
    }

    function visibleNotifications(rows) {
        var incoming = Array.isArray(rows) ? rows : [];
        var hidden = hiddenNotifications || {};
        var nextHidden = {};
        var visible = [];
        for (var i = 0; i < incoming.length; i++) {
            var item = incoming[i];
            var id = threadId(item);
            if (hidden[id])
                nextHidden[id] = item;
            else
                visible.push(item);
        }
        hiddenNotifications = nextHidden;
        return visible;
    }

    function enqueueMark(id, mode) {
        var value = String(id || "");
        var kind = mode === "done" ? "done" : "read";
        if (value === "")
            return ;
        var token = kind + ":" + value;
        if (markingNotificationId === value && markingMode === kind)
            return ;

        for (var i = 0; i < markQueue.length; i++) {
            if (markQueue[i] === token)
                return ;
        }
        markQueue = markQueue.concat([token]);
    }

    function startQueuedMark() {
        if (markProcess.running || markQueue.length === 0)
            return false;

        var token = String(markQueue[0] || "");
        markQueue = markQueue.slice(1);
        var sep = token.indexOf(":");
        var kind = sep > 0 ? token.substring(0, sep) : "read";
        var value = sep > 0 ? token.substring(sep + 1) : token;
        if (value === "")
            return startQueuedMark();

        actionStatusTimer.stop();
        markingNotificationId = value;
        markingMode = kind === "done" ? "done" : "read";
        notificationActionStatus = markingMode === "done" ? "Marking notification done…" : "Marking notification read…";
        _markStdout = "";
        _markStderr = "";
        markProcess.command = [helperPath(), markingMode === "done" ? "--mark-notification-done" : "--mark-notification-read", value];
        markProcess.running = true;
        return true;
    }

    function startPhase(phase, thenActions) {
        fetchPhase = phase;
        followUpActions = thenActions !== false;
        if (phase === "inbox" && login === "" && notifications.length === 0)
            loading = true;
        if (phase === "inbox")
            inboxLoading = true;
        else
            actionsLoading = true;
        _stdout = "";
        _stderr = "";
        fetchProcess.command = command(phase);
        fetchProcess.running = true;
    }

    function refresh(force) {
        var forced = force === true;
        if (!forced && isFresh()) {
            if (actionsFetchedAt === "" && !actionsLoading && !fetchProcess.running)
                startPhase("actions", false);
            return ;
        }
        if (fetchProcess.running || markProcess.running || markQueue.length > 0) {
            refreshQueued = true;
            return ;
        }
        refreshQueued = false;
        startPhase("inbox", true);
    }

    function apply(raw) {
        try {
            var data = JSON.parse(String(raw || ""));
            var phase = String(data.phase || "all");
            state = String(data.state || "error");
            message = String(data.message || "");
            if (String(data.login || "") !== "")
                login = String(data.login);
            if (phase !== "actions")
                fetchedAt = String(data.fetchedAt || fetchedAt);
            if (phase !== "inbox")
                actionsFetchedAt = String(data.actionsFetchedAt || data.fetchedAt || actionsFetchedAt);
            if (phase !== "actions") {
                notifications = visibleNotifications(data.notifications);
                notificationsRevision++;
                reviewRequests = Array.isArray(data.reviewRequests) ? data.reviewRequests : [];
                assignedIssues = Array.isArray(data.assignedIssues) ? data.assignedIssues : [];
                myPullRequests = Array.isArray(data.myPullRequests) ? data.myPullRequests : [];
                myPullRequestsTotal = Number(data.myPullRequestsTotal) || myPullRequests.length;
            }
            if (phase !== "inbox") {
                actions = Array.isArray(data.actions) ? data.actions : [];
                failedActions = Array.isArray(data.failedActions) ? data.failedActions : [];
                repositories = Array.isArray(data.repositories) ? data.repositories : repositories;
            }
            warnings = Array.isArray(data.warnings) ? data.warnings : warnings;
            if (data.rateLimit)
                rateLimit = data.rateLimit;
        } catch (error) {
            state = "error";
            message = "GitHub returned an unreadable response.";
            warnings = [String(error)];
        }
    }

    function markNotificationRead(id) {
        var value = String(id || "");
        if (value === "")
            return ;

        hideNotification(value);
        enqueueMark(value, "read");
        startQueuedMark();
    }

    function markNotificationDone(id) {
        var value = String(id || "");
        if (value === "")
            return ;

        hideNotification(value);
        enqueueMark(value, "done");
        startQueuedMark();
    }

    // Snapshot is "revision:id,id,id". QML's JSON.parse does not always yield a
    // real Array, so Array.isArray(snapshot.ids) dropped every bulk mark.
    function notificationIdList(rows) {
        var ids = [];
        var seen = {};
        var list = rows || [];
        for (var i = 0; i < list.length; i++) {
            var id = threadId(list[i]);
            if (!/^\d+$/.test(id))
                return null;
            if (seen[id])
                continue;
            seen[id] = true;
            ids.push(id);
        }
        return ids;
    }

    function markAllSnapshot(ids) {
        return ids.join(",");
    }

    function idsFromSnapshot(prepared) {
        var parts = String(prepared || "").split(",");
        var ids = [];
        for (var i = 0; i < parts.length; i++) {
            if (/^\d+$/.test(parts[i]))
                ids.push(parts[i]);
        }
        return ids;
    }

    // Capture the exact displayed thread IDs on the first click. The panel binds
    // confirmation to notificationsRevision, so any refresh invalidates this
    // prepared value before the destructive second click can run. Only these IDs
    // are PATCHed; a last_read_at bulk mark is never used.
    function prepareMarkAllNotificationsRead() {
        if (markProcess.running) {
            notificationActionStatus = "A mark-as-read is already running.";
            actionStatusTimer.restart();
            return "";
        }
        if (notifications.length === 0)
            return "";

        var ids = notificationIdList(notifications);
        if (!ids || ids.length === 0) {
            notificationActionStatus = "Refresh before marking everything read.";
            actionStatusTimer.restart();
            return "";
        }
        return markAllSnapshot(ids);
    }

    function markAllNotificationsRead(prepared) {
        var confirmed = String(prepared || "");
        if (confirmed === "" || markProcess.running)
            return ;

        // Recompute immediately before starting. This protects non-panel callers
        // as well as the panel's revision-bound confirmation.
        if (confirmed !== prepareMarkAllNotificationsRead()) {
            notificationActionStatus = "Notifications changed. Confirm again.";
            actionStatusTimer.restart();
            return ;
        }

        var ids = idsFromSnapshot(confirmed);
        if (ids.length === 0) {
            notificationActionStatus = "Refresh before marking everything read.";
            actionStatusTimer.restart();
            return ;
        }

        actionStatusTimer.stop();
        markingAllNotifications = true;
        markingAllNotificationIds = hideAllNotifications();
        notificationActionStatus = "Marking all notifications read…";
        _markStdout = "";
        _markStderr = "";
        var commandLine = [helperPath()];
        for (var i = 0; i < ids.length; i++)
            commandLine.push("--mark-notification-read", String(ids[i]));
        markProcess.command = commandLine;
        markProcess.running = true;
    }

    visible: false

    Component.onCompleted: {
        cacheRead.command = ["cat", cachePath()];
        cacheRead.running = true;
    }

    Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.refresh(true)
    }

    Timer {
        interval: 25000
        repeat: true
        running: root.actionCount > 0
        onTriggered: {
            if (!fetchProcess.running && !markProcess.running)
                root.startPhase("actions", false);
        }
    }

    Timer {
        id: actionStatusTimer

        interval: 3000
        repeat: false
        onTriggered: root.notificationActionStatus = ""
    }

    Process {
        id: cacheRead

        running: false
        command: ["cat", "/dev/null"]
        onExited: function(exitCode) {
            if (exitCode === 0) {
                var stdout = String(cacheOutput.text || "");
                if (stdout.trim() !== "")
                    root.apply(stdout);
            }
            Qt.callLater(function() { root.refresh(false); });
        }

        stdout: StdioCollector {
            id: cacheOutput

            waitForEnd: true
        }
    }

    Process {
        id: fetchProcess

        running: false
        command: []
        onExited: function(exitCode) {
            var phase = root.fetchPhase;
            var stdout = String(output.text || root._stdout || "");
            var stderr = String(errors.text || root._stderr || "").trim();
            if (stdout.trim() !== "") {
                root.apply(stdout);
            } else if (phase !== "actions") {
                root.state = "error";
                root.message = stderr !== "" ? stderr : "GitHub data refresh failed.";
            }
            if (phase === "inbox") {
                root.loading = false;
                root.inboxLoading = false;
                if (root.followUpActions) {
                    root.startPhase("actions", false);
                    return ;
                }
                root.actionsLoading = false;
            } else {
                root.actionsLoading = false;
            }
            if (root.startQueuedMark())
                return ;

            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(function() { root.refresh(true); });
            }
        }

        stdout: StdioCollector {
            id: output

            waitForEnd: true
            onStreamFinished: root._stdout = text
        }

        stderr: StdioCollector {
            id: errors

            waitForEnd: true
            onStreamFinished: root._stderr = text
        }

    }

    Process {
        id: markProcess

        running: false
        command: []
        onExited: function(exitCode) {
            var response = null;
            try {
                response = JSON.parse(String(markOutput.text || root._markStdout || ""));
            } catch (error) {
            }
            var all = root.markingAllNotifications;
            var markedId = root.markingNotificationId;
            var mode = root.markingMode;
            if (exitCode === 0 && response && response.state === "ready") {
                root.notificationActionStatus = all ? "Notifications marked read. Updating…" : (mode === "done" ? "Notification marked done." : "Notification marked read.");
            } else {
                var fallback = all ? "Could not mark all notifications read." : (mode === "done" ? "Could not mark notification done." : "Could not mark notification read.");
                root.notificationActionStatus = response && response.message ? String(response.message) : String(markErrors.text || root._markStderr || fallback).trim();
                if (all)
                    root.restoreHiddenNotifications(root.markingAllNotificationIds);
                else if (markedId !== "")
                    root.restoreHiddenNotification(markedId);
            }
            root.markingNotificationId = "";
            root.markingMode = "read";
            root.markingAllNotifications = false;
            root.markingAllNotificationIds = [];
            actionStatusTimer.restart();
            if (root.startQueuedMark())
                return ;

            root.refreshQueued = false;
            Qt.callLater(function() { root.startPhase("inbox", false); });
        }

        stdout: StdioCollector {
            id: markOutput

            waitForEnd: true
            onStreamFinished: root._markStdout = text
        }

        stderr: StdioCollector {
            id: markErrors

            waitForEnd: true
            onStreamFinished: root._markStderr = text
        }

    }

}
