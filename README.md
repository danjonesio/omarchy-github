# Omarchy GitHub

Your GitHub work, directly in the Omarchy bar.

**Omarchy GitHub** turns the Octocat in your bar into a fast, keyboard-friendly command center for everything that needs your attention—without keeping another browser tab open.

This is a fork of [robzolkos/omarchy-github](https://github.com/robzolkos/omarchy-github). It keeps the original dashboard and adds stricter URL handling, repository-name validation, and mark-as-read that only PATCHes the notification IDs the panel confirmed.

![Omarchy GitHub dashboard showing notifications, review requests, and assigned issues](preview.png)

## Everything waiting for you, in one panel

The dashboard is ordered by urgency so the most actionable work appears first:

- **Unread notifications** — up to 20 rows at a time; open the thread, mark it read, or mark it Done
- **Review requests** — see pull requests waiting on your review
- **My pull requests** — track the pull requests you opened and the state of their checks
- **Assigned issues** — keep track of open issues assigned to you
- **Running Actions** — pinned to omarchy and NetCask; live rows show the job pipeline (`Setup ✓ · Build ● · Test ○`) and current step

## Highlights

- Native Omarchy Quattro bar widget with an Octocat icon that lights for unread notifications, failing checks on your own PRs, or a running watch-list Action
- Compact previews that keep busy accounts readable
- Direct links to notifications, pull requests, issues, and workflow runs
- One-click notification mark-as-read, confirmed by GitHub before removal
- Bulk mark-as-read behind a confirmation step, PATCHing only the confirmed thread IDs
- Complete paginated notification fetching
- Actions scanning pinned to a short watch list, with bounded concurrency
- Graceful partial results when an endpoint or repository is unavailable
- Explicit logged-out, rate-limited, missing CLI, loading, and error states
- Mouse and keyboard navigation throughout
- Uses the existing GitHub CLI credential store—no token configuration or secret files

## Requirements

- Omarchy Quattro with shell plugin support
- [`gh`](https://cli.github.com/) on `PATH`
- [`jq`](https://jqlang.github.io/jq/)
- A Nerd Font; Omarchy includes one by default

Authenticate GitHub CLI before installing:

```bash
gh auth login
gh auth status
```

The `notifications` scope is required to read notifications and mark threads read.

Classic GitHub tokens have no read-only private-repository scope. `repo` can see private repositories, but it also grants write access this widget never uses. Prefer a **read-only fine-grained personal access token** with:

- Notifications: read and write (needed to mark threads read)
- Metadata, Issues, Pull requests, and Actions: read

Public-only accounts can skip `repo` entirely:

```bash
gh auth refresh -h github.com -s notifications
```

If you already use a classic token and need private metadata, `repo` is the GitHub limitation, not extra privilege this plugin asks for:

```bash
gh auth refresh -h github.com -s notifications -s repo
```

Omarchy GitHub delegates authentication entirely to `gh`. It does not read, copy, log, or persist your GitHub token. Opened links are restricted to `https://github.com/` and `https://gist.github.com/`.

## Install

Install directly from GitHub and enable the widget:

```bash
omarchy plugin add https://github.com/danjonesio/omarchy-github.git --enable
```

The widget defaults to the right side of the bar. To choose its position interactively:

```bash
omarchy bar move io.github.danjonesio.github
```

Confirm the installation:

```bash
omarchy plugin list | grep io.github.danjonesio.github
```

Live IPC (for debugging the running widget):

```bash
omarchy-shell io.github.danjonesio.github open
omarchy-shell io.github.danjonesio.github debug
omarchy-shell io.github.danjonesio.github clickMarkAll   # arms Confirm?
omarchy-shell io.github.danjonesio.github confirmMarkAll # PATCHes the armed IDs
```

### Update

```bash
omarchy plugin update io.github.danjonesio.github
```

If your Omarchy version only supports updating all third-party plugins:

```bash
omarchy plugin update
```

### Remove

```bash
omarchy plugin remove io.github.danjonesio.github
```

## Controls

| Input | Action |
| --- | --- |
| Left click Octocat | Open or close the dashboard |
| Right or middle click Octocat | Refresh |
| Click a row | Open it on GitHub; notification rows are also marked read |
| Gear button in the panel header | Open the settings page |
| Check button on a notification | Mark the thread read immediately, then confirm with GitHub |
| Archive button on a notification | Mark the thread **Done** |
| `d` | Mark the highlighted notification done |
| **Mark all read** in the notifications footer | Arm the bulk mark-as-read |
| **Confirm?** on the armed button | Mark every notification on screen read |
| `j` / `k` or arrow keys | Move through visible rows |
| `Enter` / `Space` | Open the highlighted row |
| `m` | Mark the highlighted notification read |
| `r` | Refresh |
| `Escape` | Close the panel |

Rows open through `omarchy-launch-webapp` by default, so GitHub gets a dedicated app window rather than a tab in an already-crowded browser. That helper targets Chromium-based default browsers and falls back to `chromium.desktop`; if you have no Chromium-based browser, switch **Open links** to **Browser tab** and rows open through `xdg-open` using your default URL handler instead. This also lets a workspace-aware browser launcher choose the destination without a separate focus command switching workspaces first.

Notifications show 20 rows per page. Other activity sections show five items initially and expand to a bounded list of 25. **Open in GitHub** takes you to the corresponding complete GitHub view where one is available. When nothing is running, a last-failure caption links to the most recent failed watch-list run.

The notifications footer also carries **Mark all read**. The first click captures the displayed notification IDs and changes the label to **Confirm?**; only the second click sends the request. Each confirmed thread is marked with `PATCH /notifications/threads/:id`. Threads that never appeared in the panel are left unread. The confirmation lapses after a few seconds, when the panel closes, when a refresh changes the notification list, and whenever another mark is running. The dashboard refreshes from GitHub after every attempt; large inboxes processed asynchronously may briefly retain threads that are already on their way out.

## Settings

**Open links** and **Refresh interval** are editable in the panel through the gear button. Changes are written to the widget's entry in `shell.json` and apply immediately. The inbox loads first; Actions fill in afterwards. Opening the panel reuses a cache if it is less than a minute old. While a watch-list run is live, Actions are polled about every 25 seconds.

| Setting | Default |
| --- | --- |
| Refresh interval | 900 seconds (15 minutes) |
| Open links | **Web app window** |

Actions are pinned to `omacom/omarchy` and `NetCask-Labs/NetCask-commercial`. Override the list in `~/.config/omarchy/github.json`:

```json
{
  "actionRepos": [
    "omacom/omarchy",
    "NetCask-Labs/NetCask-commercial"
  ]
}
```

## Local development

From an existing checkout, validate and test the plugin:

```bash
omarchy plugin validate .
tests/helper-test.sh
tests/panel-source-test.sh
tests/service-source-test.sh
```

Install that checkout for local iteration:

```bash
omarchy plugin add "$PWD" --enable
```

The shell watches local plugin files, making QML iteration fast.

## How it works

`Service.qml` schedules an executable helper, `omarchy-github-fetch`, which calls GitHub exclusively through `gh api` and processes responses with `jq`.

- REST retrieves notifications and workflow runs on the watch list.
- GitHub issue search retrieves review requests and assigned issues.
- GraphQL search retrieves your authored pull requests together with the head commit's `statusCheckRollup`, so check state costs no extra request.
- Live runs fetch jobs so the panel can show the pipeline stage.
- Independent requests allow successful sections to remain available when one endpoint fails.

Run the helper directly to inspect its JSON output:

```bash
./omarchy-github-fetch --watch-repo omacom/omarchy --phase all | jq
```

## License

MIT
