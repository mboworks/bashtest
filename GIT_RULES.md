# Git and pull-request rules

These rules are the source of truth for branch, pull-request, CI, and merge operations in this
repository. They apply to human and automated contributors. Repository protections are constraints
to satisfy, never obstacles to bypass.

## State-changing operations

Before pushing, rebasing, retargeting, merging, closing, reopening, or otherwise changing GitHub
state:

1. Fetch the current base branch and pull-request head.
2. Read the pull request's current head SHA, base, mergeability, review state, and required checks
   from GitHub.
3. Confirm that the operation advances the stated goal and does not invalidate a ready pull request
   or another change that depends on it.
4. Identify the exact branch, pull request, or run being changed. Never rely on a stale local or
   remembered state.

Keep local and remote state distinct. A local branch containing current `main` does not prove that
the remote pull-request head is current. Push synchronization commits before treating later local
validation as authoritative.

Do not force-push, rebase, retarget, merge another branch into a pull request, cancel runs, or alter
a ready pull request speculatively. Such changes are appropriate only to resolve a demonstrated
failure, conflict, or dependency, and require validation of the resulting head.

## Pull-request descriptions

Every pull-request description has two layers, in this order:

1. A short human-readable explanation of the outcome and why it matters.
2. An `## AG;DR` section containing the implementation details, reasoning, validation, portability
   notes, dependencies, and known limitations needed by reviewers or a future contributor.

Update the detailed section whenever a commit changes the implementation or validation. Keep the
human summary stable unless the outcome or motivation changes.

Descriptions must identify dependencies on other pull requests and any required merge order. Do
not claim that a check passed unless it ran against the current pushed head in the applicable
context.

## Review readiness and merging

A pull request is ready to merge only when all of the following are true:

- its intended base and head are current;
- it is approved and mergeable;
- all required checks for its current head have completed successfully;
- its description reflects the complete change;
- no unresolved dependency requires another pull request to merge first.

When a pull request is ready, merge it without changing its head, base, commits, or branch. Do not
restart, duplicate, bypass, transplant, or substitute required checks. Checks belong to their exact
pull-request context even when another commit has the same tree.

Enable auto-merge only after confirming the correct base and head, approval, mergeability, and
successful required checks. Auto-merge is a convenience, not a substitute for verifying readiness.

## Dependency ordering

Prefer small, independently reviewable pull requests. For a sequential tracked effort, keep one
pull request as the active merge gate and start the next item from updated `main` only after that
gate merges.

When changes must be stacked, record both ancestry and semantic dependencies. If a ready base has
one child, merge the base first; after GitHub retargets the child, require the child's checks to run
again against its new base. Do not delay a ready base for a child's now-obsolete pre-retarget run.

For multiple open pull requests, inspect more than their declared bases. Account for shared files,
APIs, build configuration, workflows, generated artifacts, and validation behavior. Merge independent
roots without invalidating ready work; serialize changes that overlap or alter one another's CI.
After every merge, push, retarget, or new commit, refresh GitHub state and recompute the order.

## CI and conflict recovery

Treat a failure as evidence to investigate, not a reason to weaken or bypass policy. Inspect the
failing job and reproduce it locally where practical. Fix the cause or document a narrowly scoped
exception permitted by repository policy, then rerun validation on the resulting pushed head.

For a conflicted pull request:

1. Verify that it is not already ready to merge.
2. Refresh its base and identify the exact conflicting changes.
3. Resolve the conflict on that pull request's branch, preserving compatible behavior.
4. Run validation appropriate to the combined change and push the resolution.
5. Update the description and treat all previous checks for the old head as obsolete.

Cancel only runs that are demonstrably obsolete. A slow, queued, or temporarily failing run does
not by itself justify replacing the head or starting duplicate runs.

## Completion checks

After a pull request merges:

1. Confirm GitHub reports it as merged and record the merge commit.
2. Verify that `main` contains the intended change.
3. Inspect the resulting `main` CI and address any regression before declaring the work complete or
   advancing a dependent change.
4. Refresh remaining pull requests because bases, conflicts, and required checks may have changed.
5. Remove or leave remote branches according to repository settings; never delete unmerged work
   without explicit authorization.

Work is complete only when the intended change is present on `main`, required post-merge automation
is healthy, and no promised dependent action remains.
