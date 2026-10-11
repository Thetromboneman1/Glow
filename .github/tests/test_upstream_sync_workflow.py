#!/usr/bin/env python3
"""Regression checks for the trusted upstream-sync workflow boundary."""

from pathlib import Path
import re
import os
import subprocess
import tempfile
import textwrap


WORKFLOW = Path(__file__).parents[1] / "workflows" / "upstream-sync.yml"
text = WORKFLOW.read_text(encoding="utf-8")


def require(pattern: str, message: str) -> None:
    if re.search(pattern, text, flags=re.MULTILINE) is None:
        raise AssertionError(message)


# Concurrent dispatches must serialize, and repeated runs for the same exact
# base/upstream pair must resolve to one deterministic review branch.
require(r"^\s*group: upstream-sync-\$\{\{ github\.repository \}\}$", "missing repository-wide synchronization lock")
require(r"^\s*cancel-in-progress: false$", "running synchronization must not be canceled")
require(
    r'branch="automation/upstream-sync-\$\{UPSTREAM_SHA\}-\$\{BASE_SHA\}"',
    "review branch must be stable for an exact base/upstream pair",
)
assert "GITHUB_RUN_ID" not in text and "GITHUB_RUN_ATTEMPT" not in text

finalize = text.split("- name: Publish exact validated tree without executing it", 1)[1]
finalize = finalize.split("\n  report-conflict:", 1)[0]
lookup = finalize.index('existing=$(gh pr list --head "$branch"')
push = finalize.index('git push --set-upstream origin "HEAD:refs/heads/$branch"')
assert lookup < push, "an existing exact-pair PR must be reused before pushing"
assert 'test "$existing_base" = "$BASE_SHA"' in finalize
assert 'test "$existing_cross_repo" = "false"' in finalize
assert 'test "$origin_head" = "$existing_head"' in finalize
assert 'test "$(git rev-parse "${existing_head}^{tree}")" = "$EXPECTED_TREE"' in finalize
assert 'test "$(git show -s --format=%P "$existing_head")" = "$expected_parents"' in finalize
assert 'published_head=$(git ls-remote --heads origin "refs/heads/${branch}"' in finalize
assert 'test "$(git rev-parse "${published_head}^{tree}")" = "$EXPECTED_TREE"' in finalize
assert 'test "$(git show -s --format=%P "$published_head")" = "$expected_parents"' in finalize
assert 'if [[ "$pr_base" != "$BASE_SHA" ]]' in finalize
assert 'if [[ "$pr_head" != "$published_head" ]]' in finalize

run_marker = "        run: |\n"
finalize_shell = textwrap.dedent(finalize.split(run_marker, 1)[1])


def run_finalizer(
    *,
    existing_url: str = "",
    remote_head: str = "",
    remote_parents: str = "",
    remote_tree: str = "",
    expected_parents: str = "",
    cross_repository: str = "false",
    expected_status: int = 0,
) -> str:
    with tempfile.TemporaryDirectory() as directory:
        log = Path(directory) / "commands.log"
        summary = Path(directory) / "summary.md"
        harness = r'''
git() {
  printf 'git %s\n' "$*" >> "$COMMAND_LOG"
  if [[ "$1" == "ls-remote" && "$2" == "--heads" ]]; then
    [[ -z "$REMOTE_HEAD" ]] || printf '%s\trefs/heads/test\n' "$REMOTE_HEAD"
  elif [[ "$1" == "ls-remote" ]]; then
    printf '%s\trefs/heads/main\n' "$BASE_SHA"
  elif [[ "$1" == "rev-parse" ]]; then
    case "$2" in
      HEAD) printf '%s\n' "$PUBLISHED_HEAD" ;;
      'HEAD^{tree}') printf '%s\n' "$EXPECTED_TREE" ;;
      *) printf '%s\n' "$REMOTE_TREE" ;;
    esac
  elif [[ "$1" == "show" ]]; then
    if [[ "${4-}" == "HEAD" ]]; then printf '%s\n' "$EXPECTED_PARENTS"; else printf '%s\n' "$REMOTE_PARENTS"; fi
  fi
}
gh() {
  printf 'gh %s\n' "$*" >> "$COMMAND_LOG"
  if [[ "$1 $2" == "pr list" ]]; then
    printf '%s\n' "$EXISTING_URL"
  elif [[ "$1 $2" == "pr create" ]]; then
    printf '%s\n' 'https://example.invalid/pull/1'
  elif [[ "$1 $2" == "pr view" ]]; then
    case "$*" in
      *baseRefOid*) printf '%s\n' "$BASE_SHA" ;;
      *headRefOid*)
        if [[ -n "$EXISTING_URL" ]]; then printf '%s\n' "$EXISTING_HEAD"; else printf '%s\n' "$PUBLISHED_HEAD"; fi
        ;;
      *isCrossRepository*) printf '%s\n' "$CROSS_REPOSITORY" ;;
    esac
  fi
}
'''
        env = os.environ | {
            "BASE_SHA": "a" * 40,
            "UPSTREAM_SHA": "b" * 40,
            "EXPECTED_TREE": "c" * 40,
            "EXPECTED_PARENTS": expected_parents or f'{"a" * 40} {"b" * 40}',
            "PUBLISHED_HEAD": "d" * 40,
            "EXISTING_HEAD": "e" * 40,
            "EXISTING_URL": existing_url,
            "REMOTE_HEAD": remote_head,
            "REMOTE_PARENTS": remote_parents or expected_parents or f'{"a" * 40} {"b" * 40}',
            "REMOTE_TREE": remote_tree or "c" * 40,
            "CROSS_REPOSITORY": cross_repository,
            "DOWNSTREAM_BRANCH": "main",
            "UPSTREAM_REPOSITORY": "example/upstream",
            "GH_TOKEN": "fixture-only",
            "COMMAND_LOG": str(log),
            "GITHUB_STEP_SUMMARY": str(summary),
        }
        result = subprocess.run(
            ["bash", "-c", harness + finalize_shell],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        assert result.returncode == expected_status, result.stderr
        return log.read_text(encoding="utf-8")


repeated = run_finalizer(existing_url="https://example.invalid/pull/1", remote_head="e" * 40)
assert "git push" not in repeated and "gh pr create" not in repeated
fast_forward_parents = "8" * 40
fast_forward_reuse = run_finalizer(
    existing_url="https://example.invalid/pull/ff",
    remote_head="e" * 40,
    expected_parents=fast_forward_parents,
)
assert "git push" not in fast_forward_reuse and "gh pr create" not in fast_forward_reuse
foreign = run_finalizer(
    existing_url="https://example.invalid/pull/2",
    remote_head="e" * 40,
    cross_repository="true",
    expected_status=1,
)
assert "git push" not in foreign and "gh pr create" not in foreign
wrong_origin = run_finalizer(
    existing_url="https://example.invalid/pull/3",
    remote_head="f" * 40,
    expected_status=1,
)
assert "git push" not in wrong_origin and "gh pr create" not in wrong_origin
wrong_parents = run_finalizer(
    existing_url="https://example.invalid/pull/4",
    remote_head="e" * 40,
    remote_parents="9" * 40,
    expected_status=1,
)
assert "git push" not in wrong_parents and "gh pr create" not in wrong_parents
wrong_tree = run_finalizer(
    existing_url="https://example.invalid/pull/5",
    remote_head="e" * 40,
    remote_tree="7" * 40,
    expected_status=1,
)
assert "git push" not in wrong_tree and "gh pr create" not in wrong_tree
fresh = run_finalizer()
assert "git push --set-upstream" in fresh and "gh pr create" in fresh
recovered = run_finalizer(remote_head="d" * 40)
assert "git push" not in recovered and "gh pr create" in recovered
fast_forward_recovered = run_finalizer(
    remote_head="d" * 40,
    expected_parents=fast_forward_parents,
)
assert "git push" not in fast_forward_recovered and "gh pr create" in fast_forward_recovered
wrong_recovered_parents = run_finalizer(
    remote_head="d" * 40,
    remote_parents="9" * 40,
    expected_status=1,
)
assert "git push" not in wrong_recovered_parents and "gh pr create" not in wrong_recovered_parents
wrong_recovered_tree = run_finalizer(
    remote_head="d" * 40,
    remote_tree="7" * 40,
    expected_status=1,
)
assert "git push" not in wrong_recovered_tree and "gh pr create" not in wrong_recovered_tree

# Every credential-free fetch of candidate upstream data has the documented
# bounded three-attempt retry with finite exponential backoff.
assert text.count("for attempt in 1 2 3; do") == 3
assert text.count('if [[ "$attempt" == 3 ]]; then') == 3
assert text.count("sleep $((2 ** (attempt - 1)))") == 3
assert text.count('git fetch --no-tags "https://github.com/${UPSTREAM_REPOSITORY}.git"') == 3

retry_blocks = re.findall(
    r"^          for attempt in 1 2 3; do\n.*?^          done$",
    text,
    flags=re.MULTILINE | re.DOTALL,
)
assert len(retry_blocks) == 3
for block in retry_blocks:
    shell = textwrap.dedent(block)
    harness = f'''\
set -u
attempts=0
git() {{
  attempts=$((attempts + 1))
  if (( attempts <= FAILURES )); then return 75; fi
  return 0
}}
sleep() {{ :; }}
{shell}
printf '%s\\n' "$attempts"
'''
    env = os.environ | {
        "FAILURES": "2",
        "UPSTREAM_REPOSITORY": "example/upstream",
        "UPSTREAM_SHA": "a" * 40,
    }
    recovered = subprocess.run(["bash", "-c", harness], env=env, text=True, capture_output=True, check=False)
    assert recovered.returncode == 0 and recovered.stdout.strip() == "3", recovered.stderr
    env["FAILURES"] = "3"
    exhausted = subprocess.run(["bash", "-c", harness], env=env, text=True, capture_output=True, check=False)
    assert exhausted.returncode == 1, "fetch must fail after exactly three attempts"

print("PASS upstream synchronization retry, exact-topology, and PR-reuse controls")
