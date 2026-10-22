---
name: release
description: Releases ClawBar from main. It picks the next version from what merged since the last tag, writes the release notes, tags the release, and publishes the GitHub release with the app zip. Use when the user asks to release, cut or ship a version.
---

# Release ClawBar

`release.py` beside this file does the mechanics and refuses any state or input it can't use. Your part is the
judgement: what kind each change is, and how the notes put it. Run the script as `python3 .claude/skills/release/release.py <step>`
from the repo root. Its working files sit in `build.noindex/release/`, which git ignores.

## Steps

1. **Plan.** Start from a clean `main` that matches `origin` (`git switch main && git pull --ff-only`), then run
   `plan`. It prints JSON listing every commit since the last tag, each with its files and merged PR (title, URL,
   body).
   - No commits: tell the user nothing has merged since the last tag, and stop.
   - It fails with "a prepared release is waiting at HEAD": an earlier run stopped after preparing. Ask the user
     whether to `publish` it or `abort` it.
   - Done when the plan JSON is printed and lists at least one commit.

2. **Classify** every planned commit as one kind, using the table in *Kinds*. Read each commit's PR and its diff
   outside the paths no user sees (`git show <sha> -- . ':!Tests' ':!.claude' ':!AGENTS.md'`). PR descriptions
   describe the code; the diff shows what changed for the user. If every commit is `internal`, tell the user there is nothing to release, list the commits, and stop.
   Done when every commit in the plan has a kind.

3. **Write the notes** into `build.noindex/release/release.json`:

   ```json
   {
     "kinds": { "<sha as plan printed it>": "fix", "...": "internal" },
     "summary": "One sentence naming what this release is about.",
     "changes": ["First bullet, as a full sentence.", "Second bullet."]
   }
   ```

   Read the last release (`gh release view <last_tag>`) first and write in its voice; *Notes* has the rules.
   Done when every `fix` and `feature` commit is covered by at least one bullet, and every bullet traces back to
   one of them.

4. **Prepare.** Run `prepare`, or `prepare X.Y.Z` when the user named a version. It derives the version from the
   kinds, tests, builds and checks the zip, renders `build.noindex/release/notes.md` with the Install section from
   `install.md`, then commits `Release X.Y.Z` and tags it locally. On a failure it undoes the bump; fix the cause or
   report it to the user, and keep every test as it is. Done when it prints the version, the zip and the notes path.

5. **Confirm.** Show the user the version, the kinds behind it, and `notes.md` as rendered. Ask with
   AskUserQuestion: publish, change the notes, or abort.
   - To change wording, edit `notes.md` directly; the commit doesn't contain it.
   - To change the version or a kind, run `abort`, fix `release.json`, and prepare again.

6. **Publish.** Run `publish`; if it stops after the push, run it again, as it skips what is done. Done when it
   prints the release URL. Give that URL to the user.

## Kinds

What the user sees decides the kind: the menu bar item, the menus, the widget, the files ClawBar writes
(`config.json`, `error.log`), its command-line output, the zip, and the README.

| Kind       | When                                                                                                   | Version |
|------------|--------------------------------------------------------------------------------------------------------|---------|
| `feature`  | Something new to see or do: a menu item, config key, flag or widget element, a changed default, or a removed feature | minor   |
| `fix`      | Existing behaviour corrected or improved, including closer to the original, faster, or clearer README guidance | patch   |
| `internal` | Nothing a user sees changes: tests, refactors, build scripts, `AGENTS.md`, `.claude/`                  | none    |

A commit that mixes kinds takes the highest one. While the version is 0.x, a breaking change counts as a
`feature`, and the major version moves only when the user names that version.

## Notes

- **Summary:** one sentence naming the theme, such as "Fixes from a review of the original's releases up to 1.6.0."
- **One bullet per change the user sees,** not per PR or commit. One PR can give several bullets, and two PRs can
  share one. Put the most noticeable change first.
- Write each bullet as the behaviour the user now gets, in the present tense: "X now Y", "X no longer Y". Use full
  sentences that end with a period.
- Name things the way the app shows them: menu text in its English wording, and code formatting for files, flags,
  commands and config keys (`error.log`, `--diagnose`, `claude -p`).
- Leave out what only a developer sees: type and test names, PR numbers, and how the change was made.
- A README change users would care about gets its own bullet ("The README covers ...").
