---
name: teamwork
description: "Full feature lifecycle with agent teams: Lead (PRD + issues), Developer (worktree + PR), Reviewer (code review). /teamwork [feature description or issue#]"
argument-hint: "[feature description to discuss, or issue# to resume]"
---

# Agent Team Feature Lifecycle

You are the **orchestrator**. You manage a 3-agent team that takes a feature from idea to merge-ready PR. The human does the final merge.

## Roles

| Role | Responsibility |
|------|---------------|
| **lead** | Discuss requirements with user → write PRD → create GitHub issue → manage issue/project status |
| **developer** | Pick up issue → create worktree → implement → open PR (linking issue) |
| **reviewer** | Review PR → post comments → developer fixes → re-review (max 5 rounds) |

## Step 0 — Parse Input

Parse `$ARGUMENTS`:

| Input | Action |
|-------|--------|
| Feature description (text) | Start from Step 1 — requirements discussion |
| Issue number (e.g., `#12`, `12`) | Resume — find issue status and jump to the appropriate step |
| Blank | Ask the user what they want to build |

## Step 1 — Requirements & PRD (Lead)

### 1.1 Discover GitHub Project

Before any work, the lead must find the GitHub Project associated with this repo:

```bash
gh project list --owner $(gh repo view --json owner -q '.owner.login') --format json
```

- If a project is found, use it for all status management throughout the workflow.
- If no project exists, create a local tracking file at `.claude/project-status.json` with format:
  ```json
  {
    "issues": {
      "<issue_number>": {
        "status": "Backlog|Ready|In progress|In review|Done",
        "updated_at": "<ISO timestamp>"
      }
    }
  }
  ```
- Cache the project ID for later steps.

### 1.2 Discuss with User

The lead engages the user in a focused requirements conversation:

1. Summarize understanding of the feature request
2. Ask clarifying questions (scope, constraints, acceptance criteria)
3. Propose a high-level approach
4. Iterate until the user confirms

**Do NOT proceed to PRD until the user explicitly approves the requirements.**

### 1.3 Write PRD

Create `docs/prd/<feature-slug>.md`:

```markdown
# <Feature Title>

## Overview
<!-- 1-2 sentence summary -->

## Motivation
<!-- Why this feature is needed -->

## Requirements
<!-- Numbered list of functional requirements -->

## Acceptance Criteria
<!-- Testable criteria that define "done" -->

## Technical Approach
<!-- High-level implementation strategy -->

## Out of Scope
<!-- What this feature intentionally does NOT cover -->

## Open Questions
<!-- Unresolved items, if any -->
```

### 1.4 Create GitHub Issue

```bash
gh issue create --title "<title>" --body "$(cat docs/prd/<feature-slug>.md)"
```

- The issue body IS the PRD content.
- Add relevant labels if the repo has them.
- Move issue to **Ready** in the GitHub Project (or update local status).

### 1.5 Hand Off

Report the issue number and PRD path to the orchestrator. The lead's active work pauses here until review phase or status updates are needed.

## Step 2 — Implementation (Developer)

### 2.1 Pick Up Issue

- Move issue to **In progress** (GitHub Project or local status).

### 2.2 Create Worktree

The developer MUST work in a worktree — never commit directly to main.

```bash
git worktree add .claude/worktrees/<feature-slug> -b <feature-slug> main
```

All development happens inside this worktree directory.

### 2.3 Implement

- Read the PRD and issue for requirements.
- Implement the feature in the worktree.
- Write tests as appropriate.
- Run linting, type checking, and tests if the repo has them (check CLAUDE.md for commands).
- Commit with conventional commit style: `feat(<scope>): <description>`.

### 2.4 Open PR

```bash
cd <worktree-path>
git push -u origin <feature-slug>
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<bullet points>

Closes #<issue_number>

## Test Plan
<how to verify>

## PRD
See [docs/prd/<feature-slug>.md](docs/prd/<feature-slug>.md)
EOF
)"
```

- The PR body MUST include `Closes #<issue_number>` to link the issue.
- Move issue to **In review** (GitHub Project or local status).

### 2.5 Hand Off

Report the PR number to the orchestrator. Developer pauses until review feedback arrives.

## Step 3 — Code Review (Reviewer)

### 3.1 Review PR

The reviewer reads the PR diff and the PRD, then posts review comments:

```bash
gh pr diff <pr_number>
gh pr view <pr_number>
```

Review focus areas:
- Does the implementation match the PRD requirements and acceptance criteria?
- Code quality, error handling, edge cases
- Security (OWASP top 10 awareness)
- Test coverage and quality
- Naming, structure, consistency with project conventions

### 3.2 Submit Review

```bash
gh pr review <pr_number> --comment --body "<review summary>"
```

For specific line comments, use the GitHub API:

```bash
gh api repos/{owner}/{repo}/pulls/<pr_number>/reviews --method POST \
  -f body="<summary>" \
  -f event="REQUEST_CHANGES|APPROVE" \
  -f comments='[{"path":"<file>","line":<line>,"body":"<comment>"}]'
```

The review verdict is one of:
- **APPROVE** — no issues found, PR is merge-ready
- **REQUEST_CHANGES** — issues found, developer must fix

### 3.3 Review Loop (Max 5 Rounds)

If REQUEST_CHANGES:

1. Reviewer sends findings to the orchestrator
2. Orchestrator forwards to developer
3. Developer fixes issues in the worktree, pushes new commits
4. Reviewer re-reviews the new changes
5. Repeat until APPROVE or round 5

**Round 5 rule**: If still not approved by round 5, the reviewer must produce a final summary of all remaining issues and escalate to the user for a decision. Do NOT continue beyond round 5.

Track the current round number. Each review message must state: `Review round N/5`.

### 3.4 Approved

When the reviewer approves:

1. Reviewer posts the APPROVE review on GitHub
2. Orchestrator notifies the user: "PR #N is approved and ready for merge."
3. **The human merges.** Do NOT merge the PR.

## Step 4 — Cleanup

After the user confirms the PR is merged (or you detect it via `gh pr view`):

1. Move issue to **Done** (GitHub Project or local status)
2. Remove the worktree:
   ```bash
   git worktree remove .claude/worktrees/<feature-slug>
   git branch -d <feature-slug>
   ```
3. Report completion

## Agent Team Setup

Create a team named `teamwork-<short-id>` (first 7 chars of HEAD SHA or issue number).

### Spawning

Spawn all 3 teammates at team creation, but they activate sequentially:

1. **lead** — starts immediately (Step 1)
2. **developer** — waits for lead to hand off issue number (Step 2)
3. **reviewer** — waits for developer to hand off PR number (Step 3)

Each teammate receives:
- Their role description and responsibilities from this document
- The current repo's CLAUDE.md (if it exists) for project conventions
- The GitHub project ID (or local status file path)

### Teammate Prompt Template

```
You are the {ROLE} in a feature development team.

## Your Responsibilities
{ROLE_RESPONSIBILITIES from this document}

## Project Conventions
{CLAUDE.md contents, if available}

## GitHub Project
{Project ID and status management instructions, or local status file path}

## Current State
{What has been completed so far and what you need to do next}

## Communication
- When your step is complete, send your deliverables to the team lead (orchestrator).
- If you need clarification, ask the orchestrator — they will relay to the user.
- Developer and Reviewer communicate through the orchestrator for review rounds.
```

### Worktree Usage

- Developer MUST use `git worktree add` to create an isolated working copy.
- The worktree path is `.claude/worktrees/<feature-slug>`.
- Developer works entirely within the worktree — all edits, commits, and pushes happen there.
- Worktree is cleaned up in Step 4 after merge.

## Status Management Summary

| Event | Status |
|-------|--------|
| Issue created | Ready |
| Developer starts | In progress |
| PR opened | In review |
| PR merged (by human) | Done |

For GitHub Project, use:
```bash
# Find item ID
gh project item-list <project_number> --owner <owner> --format json | jq '.items[] | select(.content.number == <issue_number>)'

# Update status
gh project item-edit --project-id <project_id> --id <item_id> --field-id <status_field_id> --single-select-option-id <option_id>
```

If the `gh project` commands fail (permissions, no project), fall back to the local `.claude/project-status.json` approach silently.

## Rules

- **Never merge PRs.** The human merges. Always.
- **Never commit to main.** All work goes through worktree + PR.
- **Max 5 review rounds.** Escalate to human after round 5.
- **PRD lives in two places:** `docs/prd/<slug>.md` AND the GitHub issue body.
- **Lead manages status.** Only the lead (or orchestrator) updates project/issue status.
- **Sequential handoff.** Each role completes before the next begins. No parallel implementation and review.
- **User approval gates:** Requirements must be approved before PRD. PRD must be approved before issue creation.
