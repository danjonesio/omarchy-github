#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-github-fetch"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_jq() { jq -e "$1" <<<"$2" >/dev/null || fail "$3"; }

bash -n "$HELPER"
"$HELPER" --help >/dev/null
if "$HELPER" --action-scan invalid >/dev/null 2>&1; then fail "invalid scan mode succeeded"; fi
if "$HELPER" --watch-repo >/dev/null 2>&1; then fail "missing watch-repo value succeeded"; fi
if "$HELPER" --watch-owner octocat >/dev/null 2>&1; then fail "dropped watch-owner option still accepted"; fi
if "$HELPER" --mark-notification-read nope >/dev/null 2>&1; then fail "invalid notification id succeeded"; fi
if "$HELPER" --mark-notification-read 123 --mark-notification-read nope >/dev/null 2>&1; then fail "invalid bulk notification id succeeded"; fi
if "$HELPER" --mark-all-read-before 2020-01-03T00:00:00Z >/dev/null 2>&1; then fail "legacy last_read_at option succeeded"; fi
if "$HELPER" --phase nope >/dev/null 2>&1; then fail "invalid phase succeeded"; fi
if "$HELPER" --mark-notification-done nope >/dev/null 2>&1; then fail "invalid done id succeeded"; fi
if "$HELPER" --repository-scope owned >/dev/null 2>&1; then fail "dropped repository-scope option still accepted"; fi
if "$HELPER" --failed-days 7 >/dev/null 2>&1; then fail "dropped failed-days option still accepted"; fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$sandbox/xdg-config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/omarchy"
export GH_TEST_LOG="$sandbox/gh-calls"
: >"$GH_TEST_LOG"
ln -s "$(command -v jq)" "$sandbox/jq"
ln -s "$(command -v bash)" "$sandbox/bash"
out=$(PATH="$sandbox" "$HELPER")
assert_jq '.state == "gh-not-installed" and (.reviewRequests|length) == 0' "$out" "missing-gh state"

cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 1; fi
exit 1
GH
chmod +x "$sandbox/gh"
out=$(PATH="$sandbox" "$HELPER")
assert_jq '.state == "logged-out" and (.repositories|length) == 0' "$out" "logged-out state"

cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 0; fi
if [[ $1 == api && $2 == user ]]; then echo octocat; exit 0; fi
if [[ $1 == api && $2 == --method && $3 == PATCH ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  id=${4##*/}
  [[ $id == 123 || $id == 124 || $id == 125 ]] || exit 9
  if [[ ${GH_FAIL_PATCH_ID:-} == "$id" ]]; then echo "boundary patch rejected ghp_abcdefghijklmnopqrstuvwxyz123456" >&2; exit 8; fi
  printf '%s\n' '{}'; exit 0
fi
if [[ $1 == api && $2 == --method && $3 == PUT ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  exit 9
fi
if [[ $1 == api && $2 == --method && $3 == DELETE ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  id=${4##*/}
  [[ $id == 123 || $id == 124 || $id == 125 ]] || exit 9
  printf '%s\n' '{}'; exit 0
fi
if [[ $1 == api && $2 == graphql ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  if [[ $* == *review-requested:@me* ]]; then
    cat <<'JSON'
{"data":{"search":{"issueCount":1,"nodes":[{"number":7,"title":"Please review","url":"https://github.com/octocat/hello/pull/7","updatedAt":"2026-01-02T00:00:00Z","isDraft":false,"reviewDecision":"REVIEW_REQUIRED","latestReviews":{"nodes":[{"state":"APPROVED"}]},"reviewRequests":{"totalCount":1},"repository":{"nameWithOwner":"octocat/hello"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}]}}}
JSON
    exit 0
  fi
  if [[ $* == *author:@me* ]]; then
    cat <<'JSON'
{"data":{"search":{"issueCount":2,"nodes":[{"number":7,"title":"Ship it","url":"https://github.com/octocat/hello/pull/7","updatedAt":"2026-01-05T00:00:00Z","isDraft":false,"reviewDecision":null,"latestReviews":{"nodes":[]},"reviewRequests":{"totalCount":2},"repository":{"nameWithOwner":"octocat/hello"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},{"number":9,"title":"No CI here","url":"https://github.com/octocat/quiet/pull/9","updatedAt":"2026-01-04T00:00:00Z","isDraft":true,"reviewDecision":"CHANGES_REQUESTED","latestReviews":{"nodes":[{"state":"CHANGES_REQUESTED"}]},"reviewRequests":{"totalCount":0},"repository":{"nameWithOwner":"octocat/quiet"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}]}}}
JSON
    exit 0
  fi
  echo "unexpected graphql" >&2
  exit 1
fi
endpoint=${*: -1}
printf '%s\n' "$*" >>"$GH_TEST_LOG"
if [[ $endpoint == /rate_limit* ]]; then
  cat <<'JSON'
{"resources":{"core":{"limit":5000,"remaining":4821,"reset":1788956168,"used":179},"search":{"limit":30,"remaining":28,"reset":1788952628,"used":2},"graphql":{"limit":5000,"remaining":4991,"reset":1788956168,"used":9}}}
JSON
  exit 0
fi
if [[ $endpoint == /notifications* ]]; then
  cat <<'JSON'
[{"id":"123","unread":true,"reason":"mention","updated_at":"2026-01-03T00:00:00Z","repository":{"full_name":"octocat/hello","html_url":"https://github.com/octocat/hello"},"subject":{"title":"Review this","type":"PullRequest","url":"https://api.github.com/repos/octocat/hello/pulls/7","latest_comment_url":null}},{"id":"124","unread":true,"reason":"subscribed","updated_at":"2026-01-02T00:00:00Z","repository":{"full_name":"octocat/hello","html_url":"https://github.com/octocat/hello"},"subject":{"title":"Unknown subject","type":"RepositoryVulnerabilityAlert","url":"https://api.github.com/repos/octocat/hello/private-vulnerability-reporting/1","latest_comment_url":"https://api.github.com/repos/octocat/hello/comments/1"}}]
JSON
  exit 0
fi
if [[ $endpoint == /search/issues\?q=is%3Aopen+is%3Aissue* ]]; then
  cat <<'JSON'
{"items":[{"id":81,"number":8,"title":"Fix it","repository_url":"https://api.github.com/repos/octocat/hello","html_url":"https://github.com/octocat/hello/issues/8","updated_at":"2026-01-02T00:00:00Z","user":{"login":"friend"}}]}
JSON
  exit 0
fi
if [[ $endpoint == /user/repos* ]]; then
  cat <<'JSON'
[{"full_name":"octocat/hello","archived":false,"fork":false,"html_url":"https://github.com/octocat/hello"}]
JSON
  exit 0
fi
if [[ $endpoint == /orgs/NetCask-Labs/repos* ]]; then
  cat <<'JSON'
[{"full_name":"NetCask-Labs/NetCask-commercial","archived":false,"fork":false,"html_url":"https://github.com/NetCask-Labs/NetCask-commercial"}]
JSON
  exit 0
fi
if [[ $endpoint == /orgs/danjonesio/repos* ]]; then
  echo "HTTP 404: Not Found" >&2
  exit 1
fi
if [[ $endpoint == /users/danjonesio/repos* ]]; then
  cat <<'JSON'
[{"full_name":"danjonesio/omardan","archived":false,"fork":false,"html_url":"https://github.com/danjonesio/omardan"},{"full_name":"danjonesio/old","archived":true,"fork":false,"html_url":"https://github.com/danjonesio/old"}]
JSON
  exit 0
fi
if [[ $endpoint == /repos/*/actions/runs/*/jobs* ]]; then
  cat <<'JSON'
{"jobs":[{"name":"Setup","status":"completed","conclusion":"success","steps":[]},{"name":"Build","status":"in_progress","conclusion":null,"steps":[{"name":"Checkout","status":"completed"},{"name":"Compile","status":"in_progress"}]},{"name":"Test","status":"queued","conclusion":null,"steps":[]}]}
JSON
  exit 0
fi
if [[ $endpoint == /repos/octocat/hello/actions/runs* ]]; then
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ $endpoint == *status=queued* ]]; then
    cat <<JSON
{"workflow_runs":[{"id":10,"name":"CI","display_title":"Build","status":"queued","conclusion":null,"head_branch":"main","html_url":"https://github.com/octocat/hello/actions/runs/10","created_at":"$now","updated_at":"$now"}]}
JSON
  elif [[ $endpoint == *status=completed* ]]; then
    cat <<JSON
{"workflow_runs":[{"id":12,"name":"Newer fail","status":"completed","conclusion":"failure","head_branch":"main","html_url":"https://github.com/octocat/hello/actions/runs/12","created_at":"$now","updated_at":"2026-01-03T00:00:00Z"},{"id":11,"name":"Test","status":"completed","conclusion":"failure","head_branch":"main","html_url":"https://github.com/octocat/hello/actions/runs/11","created_at":"$now","updated_at":"2026-01-01T00:00:00Z"}]}
JSON
  else
    printf '%s\n' '{"workflow_runs":[]}'
  fi
  exit 0
fi
if [[ $endpoint == /repos/*/actions/runs* ]]; then
  printf '%s\n' '{"workflow_runs":[]}'
  exit 0
fi
exit 1
GH
chmod +x "$sandbox/gh"
out=$(PATH="$sandbox:$PATH" "$HELPER" --watch-repo octocat/hello)
assert_jq '.state == "ready" and .login == "octocat"' "$out" "ready state"
assert_jq '.phase == "all"' "$out" "default phase is all"
assert_jq '.repositories|length == 1 and .[0].nameWithOwner == "octocat/hello"' "$out" "watch list is the scanned repository"
assert_jq '.notifications|length == 2 and .[0].url == "https://github.com/octocat/hello/pull/7" and .[1].url == "https://github.com/octocat/hello"' "$out" "type-aware notification conversion and fallback"
assert_jq '.reviewRequests|length == 1 and .[0].repository == "octocat/hello"' "$out" "review requests"
assert_jq '(.reviewRequests[0].approved == 1) and (.reviewRequests[0].requested == 2) and (.reviewRequests[0].checks == "SUCCESS")' "$out" "review requests carry approval progress and checks"
assert_jq '(.assignedIssues|length == 1) and (.assignedIssues[0].url|endswith("/issues/8"))' "$out" "assigned issues"
assert_jq '(.actions|length == 1) and (.failedActions|length == 1) and (.failedActions[0].id == 12)' "$out" "active run plus last failure per watch repo"
assert_jq '(.actions[0].jobs|length == 3) and (.actions[0].job == "Build") and (.actions[0].step == "Compile")' "$out" "live run carries job pipeline and current step"
assert_jq '(.myPullRequests|length == 2) and (.myPullRequests[0].id == "octocat/hello#7") and (.myPullRequests[0].checks == "FAILURE")' "$out" "authored pull requests with check rollup"
assert_jq '(.myPullRequests[0].approved == 0) and (.myPullRequests[0].requested == 2) and (.myPullRequests[0].changesRequested == false)' "$out" "authored PR reports 0/2 approved"
assert_jq '(.myPullRequests[1].checks == "NONE") and (.myPullRequests[1].draft == true) and (.myPullRequests[1].changesRequested == true)' "$out" "missing rollup falls back to NONE and changes requested is kept"
assert_jq '.myPullRequestsTotal == 2' "$out" "authored pull request total reported"
assert_jq '(.warnings|length) == 0' "$out" "no warnings on the happy path"
assert_jq '.rateLimit.core.used == 179 and .rateLimit.core.remaining == 4821 and .rateLimit.graphql.limit == 5000' "$out" "rate limit usage is reported"
grep -q '/rate_limit' "$GH_TEST_LOG" || fail "rate limit was not fetched"
grep -q 'author:@me.*sort:updated-desc' "$GH_TEST_LOG" || fail "authored pull request search was not server sorted"
grep -q 'author:@me.*archived:false' "$GH_TEST_LOG" || fail "authored pull request search was not archive filtered"
grep -q 'review-requested:@me' "$GH_TEST_LOG" || fail "review request search was not GraphQL"
grep -q 'review-requested:@me.*draft:false' "$GH_TEST_LOG" || fail "review request search was not draft filtered"
grep -q 'assignee%3A%40me+archived%3Afalse' "$GH_TEST_LOG" || fail "assigned issue search was not archive filtered"
grep -q '/repos/octocat/hello/actions/runs?status=queued' "$GH_TEST_LOG" || fail "watch repo was not scanned for queued Actions"
grep -q '/repos/octocat/hello/actions/runs/10/jobs' "$GH_TEST_LOG" || fail "live run did not fetch jobs"
if grep -q '/users/danjonesio/repos' "$GH_TEST_LOG"; then fail "explicit watch-repo still expanded default owners"; fi
if grep -q '/orgs/NetCask-Labs/repos' "$GH_TEST_LOG"; then fail "explicit watch-repo still listed default org repositories"; fi
if grep -q '/user/repos' "$GH_TEST_LOG"; then fail "explicit watch-repo still listed the authenticated user's repositories"; fi
if grep -- '--paginate' "$GH_TEST_LOG" | grep -q '/actions/runs'; then fail "Actions scan still paginates"; fi
if grep -q 'created=%3E%3D' "$GH_TEST_LOG"; then fail "completed Actions request was still date bounded"; fi
if grep -q 'ownerAffiliations' "$GH_TEST_LOG"; then fail "repository GraphQL listing still ran"; fi

: >"$GH_TEST_LOG"
inbox=$(PATH="$sandbox:$PATH" "$HELPER" --phase inbox --watch-repo octocat/hello)
assert_jq '.phase == "inbox" and .login == "octocat" and (.myPullRequests|length) == 2 and (.actions|length) == 0' "$inbox" "inbox phase skips actions"
if grep -q '/actions/runs' "$GH_TEST_LOG"; then fail "inbox phase still scanned Actions"; fi
if grep -q 'ownerAffiliations' "$GH_TEST_LOG"; then fail "inbox phase still listed repositories"; fi
if grep -q '/user/repos' "$GH_TEST_LOG"; then fail "inbox phase still listed owner repositories"; fi
if grep -q '/orgs/' "$GH_TEST_LOG"; then fail "inbox phase still listed organization repositories"; fi

: >"$GH_TEST_LOG"
off=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan off --watch-repo octocat/hello)
assert_jq '(.actions|length) == 0 and (.failedActions|length) == 0' "$off" "action-scan off skips Actions"
if grep -q '/actions/runs' "$GH_TEST_LOG"; then fail "action-scan off still scanned Actions"; fi

: >"$GH_TEST_LOG"
defaults=$(PATH="$sandbox:$PATH" "$HELPER" --phase actions)
assert_jq '(.repositories|length == 2) and ([.repositories[].nameWithOwner]|index("omacom/omarchy") != null) and ([.repositories[].nameWithOwner]|index("NetCask-Labs/NetCask-commercial") != null)' "$defaults" "default watch list is omarchy and NetCask"
grep -q '/repos/omacom/omarchy/actions/runs' "$GH_TEST_LOG" || fail "default watch list did not scan omarchy"
grep -q '/repos/NetCask-Labs/NetCask-commercial/actions/runs' "$GH_TEST_LOG" || fail "default watch list did not scan NetCask"
if grep -q '/user/repos' "$GH_TEST_LOG"; then fail "default watch list listed every owned repository"; fi
if grep -q '/users/danjonesio/repos' "$GH_TEST_LOG"; then fail "default watch list listed danjonesio repositories"; fi
if grep -q '/orgs/NetCask-Labs/repos' "$GH_TEST_LOG"; then fail "default watch list listed every org repository"; fi

mkdir -p "$XDG_CONFIG_HOME/omarchy"
printf '%s\n' '{"actionRepos":["octocat/hello"]}' >"$XDG_CONFIG_HOME/omarchy/github.json"
: >"$GH_TEST_LOG"
from_config=$(PATH="$sandbox:$PATH" "$HELPER" --phase actions)
assert_jq '.repositories|length == 1 and .[0].nameWithOwner == "octocat/hello"' "$from_config" "config actionRepos override the default watch list"
grep -q '/repos/octocat/hello/actions/runs' "$GH_TEST_LOG" || fail "config watch list was not scanned"
if grep -q '/repos/omacom/omarchy/actions/runs' "$GH_TEST_LOG"; then fail "default watch list used despite config"; fi
if grep -q '/user/repos' "$GH_TEST_LOG"; then fail "config actionRepos still listed owned repositories"; fi
rm -f "$XDG_CONFIG_HOME/omarchy/github.json"

printf '%s\n' '{"actionOwners":["octocat"]}' >"$XDG_CONFIG_HOME/omarchy/github.json"
: >"$GH_TEST_LOG"
from_owners=$(PATH="$sandbox:$PATH" "$HELPER" --phase actions)
assert_jq '([.repositories[].nameWithOwner]|index("omacom/omarchy") != null)' "$from_owners" "leftover actionOwners does not expand accounts"
if grep -q '/user/repos' "$GH_TEST_LOG"; then fail "actionOwners still listed repositories"; fi
if grep -q '/users/octocat/repos' "$GH_TEST_LOG"; then fail "actionOwners still expanded octocat"; fi
rm -f "$XDG_CONFIG_HOME/omarchy/github.json"

: >"$GH_TEST_LOG"
mark=$(PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 123)
assert_jq '.state == "ready" and .notificationId == "123"' "$mark" "mark notification read"
: >"$GH_TEST_LOG"
done_mark=$(PATH="$sandbox:$PATH" "$HELPER" --mark-notification-done 123)
assert_jq '.state == "ready" and .notificationId == "123" and (.message|test("done"))' "$done_mark" "mark notification done"
grep -q 'api --method DELETE /notifications/threads/123' "$GH_TEST_LOG" || fail "done did not DELETE the thread"
: >"$GH_TEST_LOG"
mark_all=$(PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 123 --mark-notification-read 124)
assert_jq '.state == "ready" and .count == 2' "$mark_all" "mark all notifications read"
mapfile -t mark_calls < <(sort "$GH_TEST_LOG")
[[ ${#mark_calls[@]} -eq 2 ]] || fail "bulk mark made an unexpected number of API calls"
[[ ${mark_calls[0]} == 'api --method PATCH /notifications/threads/123' && ${mark_calls[1]} == 'api --method PATCH /notifications/threads/124' ]] || fail "bulk mark did not patch exactly the confirmed notification ids"
if grep -q ' --method PUT ' "$GH_TEST_LOG"; then fail "bulk mark used last_read_at PUT"; fi
: >"$GH_TEST_LOG"
set +e
mark_partial=$(GH_FAIL_PATCH_ID=124 PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 123 --mark-notification-read 124 --mark-notification-read 125)
mark_partial_status=$?
set -e
[[ $mark_partial_status -eq 1 ]] || fail "partial bulk failure returned status $mark_partial_status"
assert_jq '.state == "error" and .notificationId == "124" and (.message|test("boundary patch rejected")) and (.message|contains("ghp_")|not) and (.message|contains("[REDACTED]"))' "$mark_partial" "partial bulk failure reports the failing notification without exposing credentials"
mapfile -t partial_calls < <(sort "$GH_TEST_LOG")
[[ ${#partial_calls[@]} -eq 3 && ${partial_calls[0]} == 'api --method PATCH /notifications/threads/123' && ${partial_calls[1]} == 'api --method PATCH /notifications/threads/124' && ${partial_calls[2]} == 'api --method PATCH /notifications/threads/125' ]] || fail "partial bulk failure did not patch every confirmed notification"
set +e
mark_all_failed=$(PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 999)
mark_all_failed_status=$?
set -e
[[ $mark_all_failed_status -eq 1 ]] || fail "failed bulk mark returned status $mark_all_failed_status"
assert_jq '.state == "error" and .notificationId == "999"' "$mark_all_failed" "failed mark reports an error"

mkdir "$sandbox/failbin"
cat >"$sandbox/failbin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$sandbox/failbin/mktemp"
set +e
mark_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER" --mark-notification-read 123)
mark_setup_status=$?
bulk_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER" --mark-notification-read 123 --mark-notification-read 124)
bulk_setup_status=$?
fetch_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER")
fetch_setup_status=$?
set -e
[[ $mark_setup_status -eq 1 && $bulk_setup_status -eq 1 && $fetch_setup_status -eq 1 ]] || fail "temporary-storage failures returned an unexpected status"
assert_jq '.state == "error" and .notificationId == "123"' "$mark_setup_failed" "single mark setup failure reports an error"
assert_jq '.state == "error" and .notificationId == "123"' "$bulk_setup_failed" "bulk mark setup failure reports an error"
assert_jq '.state == "error"' "$fetch_setup_failed" "refresh setup failure reports an error"

cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 0; fi
if [[ $1 == api && $2 == graphql ]]; then
  cat <<'JSON'
{"data":{"search":{"issueCount":0,"nodes":[]}}}
JSON
  exit 0
fi
if [[ $1 == api && $2 == user ]]; then echo octocat; exit 0; fi
endpoint=${*: -1}
if [[ $endpoint == /repos/octocat/hello/actions/runs* ]]; then
  echo "HTTP 403: Resource not accessible by integration" >&2
  exit 1
fi
printf '%s\n' '[]'
GH
chmod +x "$sandbox/gh"
scoped=$(PATH="$sandbox:$PATH" "$HELPER" --watch-repo octocat/hello --phase actions)
assert_jq '(.warnings|length) > 0 and (.warnings[0]|test("403"))' "$scoped" "Actions warnings keep the API error text"

cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 0; fi
printf '%s\n' "$*" >>"$GH_TEST_LOG"
if [[ $1 == api && $2 == graphql ]]; then
  if [[ $* == *review-requested:@me* ]]; then
    cat <<'JSON'
{"data":{"search":{"issueCount":1,"nodes":[{"number":7,"title":"Please review","url":"https://evil.example/pull/7","updatedAt":"2026-01-02T00:00:00Z","isDraft":false,"reviewDecision":null,"latestReviews":{"nodes":[]},"reviewRequests":{"totalCount":1},"repository":{"nameWithOwner":"octocat/hello"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}]}}}
JSON
    exit 0
  fi
  if [[ $* == *author:@me* ]]; then
    cat <<'JSON'
{"data":{"search":{"issueCount":1,"nodes":[{"number":7,"title":"Ship it","url":"javascript:alert(1)","updatedAt":"2026-01-05T00:00:00Z","isDraft":false,"repository":{"nameWithOwner":"octocat/hello"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}]}}}
JSON
    exit 0
  fi
  echo "unexpected graphql" >&2
  exit 1
fi
if [[ $1 == api && $2 == user ]]; then echo octocat; exit 0; fi
endpoint=${*: -1}
if [[ $endpoint == /notifications* ]]; then
  cat <<'JSON'
[{"id":"123","unread":true,"reason":"mention","updated_at":"2026-01-03T00:00:00Z","repository":{"full_name":"octocat/hello","html_url":"javascript:alert(1)"},"subject":{"title":"Review this","type":"PullRequest","url":"https://api.github.com/repos/octocat/hello/pulls/7"}},{"id":"124","unread":true,"reason":"subscribed","updated_at":"2026-01-02T00:00:00Z","repository":{"full_name":"octocat/hello","html_url":"https://github.com.evil.com/octocat/hello"},"subject":{"title":"Unknown","type":"RepositoryVulnerabilityAlert","url":"https://evil.example/x"}}]
JSON
  exit 0
fi
if [[ $endpoint == /search/issues* ]]; then
  cat <<'JSON'
{"items":[{"id":71,"number":7,"title":"Please review","repository_url":"https://api.github.com/repos/octocat/hello","html_url":"https://evil.example/pull/7","updated_at":"2026-01-02T00:00:00Z","user":{"login":"friend"}}]}
JSON
  exit 0
fi
if [[ $endpoint == /repos/*/actions/runs/*/jobs* ]]; then
  printf '%s\n' '{"jobs":[]}'
  exit 0
fi
if [[ $endpoint == /repos/* ]]; then
  printf '%s\n' '{"workflow_runs":[]}'
  exit 0
fi
printf '%s\n' '[]'
GH
chmod +x "$sandbox/gh"
: >"$GH_TEST_LOG"
sanitized=$(PATH="$sandbox:$PATH" "$HELPER" --watch-repo octocat/hello --watch-repo 'octocat/hello$(id)')
assert_jq '([.notifications[].url]|index("javascript:alert(1)")|not) and ([.notifications[].url]|index("https://github.com.evil.com/octocat/hello")|not)' "$sanitized" "hostile notification urls are dropped"
assert_jq '.notifications[0].url == "https://github.com/octocat/hello/pull/7" and .notifications[1].url == "https://github.com/octocat/hello"' "$sanitized" "notification urls fall back to github.com"
assert_jq '([.reviewRequests[].url]|index("https://evil.example/pull/7")|not) and (.reviewRequests[0].url == "")' "$sanitized" "hostile search urls are dropped"
assert_jq '.myPullRequests[0].url == ""' "$sanitized" "hostile authored pull request urls are dropped"
assert_jq '([.repositories[].nameWithOwner]|index("octocat/hello$(id)")|not) and ([.repositories[].nameWithOwner]|index("octocat/hello") != null)' "$sanitized" "invalid repository names are dropped"
if grep -F 'octocat/hello$(id)' "$GH_TEST_LOG"; then fail "invalid repository name reached gh api"; fi
if grep -E '/repos/[^ ]*\$' "$GH_TEST_LOG"; then fail "shell metacharacters reached an actions path"; fi

echo "helper tests passed"
