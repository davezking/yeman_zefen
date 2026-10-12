# Ops

## Code review

Every task lands on `main` only through a pull request. Two checks must pass: `CI` (`.github/workflows/ci.yml`) and `Opus review` (`.github/workflows/claude-review.yml`), which runs on every push to a PR and posts one comment ending in `VERDICT: APPROVE` or `VERDICT: CHANGES_REQUESTED`. The review always runs as `claude-opus-5-5`, regardless of which model wrote the code.

### Adding the auth secret

The review workflow authenticates with one of:

- `CLAUDE_CODE_OAUTH_TOKEN` (an OAuth token for a Claude Code subscription), or
- `ANTHROPIC_API_KEY` (a direct Anthropic API key).

Add whichever one you use as a repository secret: **Settings → Secrets and variables → Actions → New repository secret**. Only one is required; the workflow passes both inputs, and the action uses whichever is non-empty.

### Branch protection on `main`

**Settings → Branches** (or **Rulesets**, for a ruleset instead of a classic rule) → add a rule for `main`:

- Require a pull request before merging (require at least 1 approval if you want human sign-off too — Opus's approval is separate from this and is enforced by the status check below, not by this setting).
- Require status checks to pass before merging. Add:
  - `Opus review`
  - the `CI` job(s) from `ci.yml` (`api (typecheck + test)`, `ingest (pytest)`)
- Require branches to be up to date before merging.
- Do not allow bypassing the above settings (disable for admins too, if the UI offers it).
- Block force pushes.
- Restrict who can push directly to `main` — in practice, allow no one; every change goes through a PR.

With this in place, a direct `git push origin main` is rejected, and a PR cannot merge while `Opus review` shows `CHANGES_REQUESTED` or hasn't reported yet.

### False positives

If Opus's `CHANGES_REQUESTED` is wrong — a finding doesn't apply, or a checklist item is in fact satisfied — do not bypass the check or add a label that skips it; that makes the review optional in practice. Instead:

1. Reply on the PR comment thread explaining why the finding doesn't hold.
2. Re-run the `Opus review` job (re-run the failed workflow run, or push an empty-diff-safe change such as updating the PR description) so it re-evaluates with your explanation in context.
3. If Opus agrees on re-review, it posts a new comment with `VERDICT: APPROVE` and the check goes green. If it still disagrees, escalate to a human reviewer rather than overriding the check.

Pushing any new commit to the PR branch also re-runs the review automatically and cancels any run still in progress for that PR, via `concurrency: claude-review-${{ github.event.pull_request.number }}`.
