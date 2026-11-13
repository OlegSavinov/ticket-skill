---
inclusion: auto
name: ticket-defend
description: >
  Address PR review comments on a ticket. Refetches context, forms understanding,
  evaluates each comment, proposes responses, then applies agreed changes.
  Use when PR has review comments to address.
---

# Defend PR

Goal: pass code review by reaching agreement with reviewers. Disagree when right,
concede when wrong.

## Stages

### 1. Refetch context
- Fetch Jira ticket (with comments and linked issues)
- Get PR diff: `gh pr diff`
- Get PR metadata: `gh pr view --json number,title,body,headRefName`

### 2. Form understanding
State in ≤10 lines:
- **Why**: business/tech problem being solved
- **How**: current implementation approach
- **Criteria**: what "done" looks like

### 3. Fetch and evaluate comments
```bash
# Get review threads, filtering out resolved and outdated
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 10) {
              nodes { id body author { login } path line outdated }
            }
          }
        }
      }
    }
  }
' -f owner=OWNER -f repo=REPO -F pr=PR_NUMBER \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .comments.nodes[] | select(.outdated == false)'
```

For each comment returned:

**Before agreeing or disagreeing**, if the comment claims a bug or flaw, follow the
**Spec-first bug procedure** from the main skill. If you cannot produce a failing spec,
the scenario may not be real — factor that into your response.

Classify each comment:

**Disagree** — comment conflicts with ticket understanding or proposes worse solution.
Rationale must include one of:
- Similar existing code (path:line)
- Jira quote + derived understanding
- Production data showing real-world relevance

**Partially agree** — suggestion has merit but limited value. State what you'd take.

**Agree** — genuinely overlooked scenario or objectively better approach.

### 4. Gate: review responses (STOP)
Present each comment with:
- The comment text (abbreviated if long)
- Your classification + rationale (1-3 lines)
- Proposed response text

Wait for user approval/edits.

### 5. Apply
- **Agreed changes**: implement, run specs, self-review the delta
- **Push**: only after all changes are complete and verified, push the branch
- **Log**: each comment you Agree or Partially agree with is a review-caught error:
  `L review <KEY> "<what>"` (`L` as in the main skill)
- **Respond on GitHub**: only after pushing, so replies reflect pushed work; post via `gh api`

```bash
# Reply to a review comment — always prefix with 🤖🛡️
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies -f body="🤖🛡️ ..."
```

Then run the Retro section of `references/ledger.md` with the logged comments as its
events (skip `L close` if the ticket is already closed).

End with: what changed, what was defended, any unresolved items.
