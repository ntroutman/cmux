# Syncing the fork with upstream

`ntroutman/cmux` is a personal fork. Its `main` is the custom build: upstream
`manaflow-ai/cmux` plus fork-only work, kept current by merging upstream in.
Nothing is sent back upstream.

## One-time setup per clone

```bash
git remote add upstream https://github.com/manaflow-ai/cmux.git
git remote set-url --push upstream DISABLED
```

`scripts/merge-main.sh` finds upstream by that URL, not by remote name.

## Before starting new work

New worktrees branch from `origin/main`, so sync there first. In the fresh
worktree, before any feature commit:

```bash
git fetch upstream main
git rev-list --count HEAD..upstream/main   # 0 means main is current; start work
scripts/merge-main.sh                      # merges the newest upstream commit with green guards
```

`merge-main.sh` refuses to run on `main` itself, so run it on the worktree's
branch. If it merged anything, build before publishing (below), then
fast-forward the fork's `main` to the merge and carry on with feature work on
top of it:

```bash
git push origin HEAD:main
```

That push is a fast-forward and is rejected if `main` moved meanwhile; run
`git pull --no-rebase origin main` and push again. For a sync with no feature
work, use a branch named `sync/upstream-<date>` and delete it afterwards.

## When the merge conflicts

`merge-main.sh` resolves `project.pbxproj`, the config schema and `.xcstrings`
with their generators, and aborts on any other conflict, naming the paths and
the green commit. Merge that commit by hand, resolve the named paths, and
resolve `project.pbxproj` with its merge driver if git conflicts on it too:

```bash
git merge <green-commit>
P=cmux.xcodeproj/project.pbxproj; T=$(mktemp -d)
git show :1:$P > $T/base; git show :2:$P > $T/ours; git show :3:$P > $T/theirs
python3 scripts/merge-pbxproj.py $T/base $T/ours $T/theirs $P && cp $T/ours $P
python3 scripts/normalize-pbxproj.py --check $P && scripts/sync-test-wiring --check
```

Fork changes usually conflict with upstream in settings lists such as
`AppSection.swift`'s `startSettingsObservation([...])`: keep both sides' entries.
With `git config rerere.enabled true`, git reuses a resolution it has recorded
once on later syncs.

## Verifying a sync

Reuse the `sync-upstream` tag so the build cache stays warm:

```bash
CMUX_TUI_CLIENT_MAX_FALLBACK=1 CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag sync-upstream --build-only
./scripts/test-unit.sh -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-sync-upstream-tests" build-for-testing
```

`CMUX_TUI_CLIENT_MAX_FALLBACK=1` lets the build bundle the previous published
cmux-tui client when upstream has not yet published one for the newest
cmux-tui inputs. Upstream's own tip hits the same gap.

## Merging into `main`

Never squash-merge into `main`, whether a sync or a feature PR whose branch
merged upstream. A squash drops the upstream ancestry, and every later sync
then conflicts on everything it already merged. Use a fast-forward or a merge
commit.
