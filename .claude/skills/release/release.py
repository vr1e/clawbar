#!/usr/bin/env python3
"""The mechanical half of a ClawBar release; SKILL.md beside it says when to run each step.

plan     lists what main holds since the last tag, as JSON
prepare  bumps the version, tests, builds and zips the app, renders the notes, commits and tags locally
publish  pushes the release commit and tag, and creates the GitHub release with the zip
abort    drops a prepared release that was never pushed, keeping release.json
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / "build.noindex"
WORK = BUILD / "release"
RELEASE = WORK / "release.json"
NOTES = WORK / "notes.md"
INSTALL = Path(__file__).with_name("install.md")
APP = BUILD / "ClawBar.app"
SWIFT_VERSION = ROOT / "Sources" / "ClawBarShared" / "AppPaths.swift"
PLIST = ROOT / "Resources" / "Info.plist"
KINDS = ("feature", "fix", "internal")


def fail(message):
    sys.exit(f"release: {message}")


def run(*args, check=True):
    r = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        fail(f"{' '.join(args)} failed:\n{r.stderr.strip() or r.stdout.strip()}")
    return r.stdout.strip()


def step(*args):
    """Runs a long step quietly, showing the end of its output only when it fails."""
    r = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print("\n".join((r.stdout + r.stderr).splitlines()[-40:]), file=sys.stderr)
        fail(f"{' '.join(args)} failed")


def zip_path(version):
    return WORK / f"ClawBar-{version}-arm64.zip"


def current_version():
    m = re.search(r'public static let version = "([^"]+)"', SWIFT_VERSION.read_text())
    if not m:
        fail(f"no version line in {SWIFT_VERSION.relative_to(ROOT)}")
    return m.group(1)


def parse(version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        fail(f"{version} is not MAJOR.MINOR.PATCH")
    return tuple(int(p) for p in version.split("."))


def on_clean_main():
    if run("git", "branch", "--show-current") != "main":
        fail("check out main first (git switch main && git pull --ff-only)")
    if run("git", "status", "--porcelain"):
        fail("the working tree has changes; commit or stash them first")


def on_synced_main():
    """main checked out, clean, and equal to origin/main after a fetch."""
    on_clean_main()
    run("git", "fetch", "--quiet", "--tags", "origin")
    if run("git", "rev-parse", "HEAD") != run("git", "rev-parse", "origin/main"):
        if run("git", "log", "-1", "--format=%s") == f"Release {current_version()}":
            fail("a prepared release is waiting at HEAD; publish or abort it")
        fail("main differs from origin/main; pull or push first")


def since_tag():
    """The last release tag and the commits on main after it, oldest first, as (short sha, full sha, subject)."""
    tag = run("git", "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", "HEAD")
    if tag != f"v{current_version()}":
        fail(f"the code says {current_version()} but the last tag is {tag}: a PR bumped the version, "
             "or a release is half done")
    log = run("git", "log", "--first-parent", "--reverse", "--format=%H%x1f%s", f"{tag}..HEAD")
    return tag, [(sha[:9], sha, subject) for sha, subject in (l.split("\x1f", 1) for l in log.splitlines() if l)]


def plan():
    on_synced_main()
    run("gh", "auth", "status")
    tag, commits = since_tag()
    listed = []
    for short, sha, subject in commits:
        # Per commit rather than one PR listing, so a rebase-merged PR's every commit still finds it.
        pulls = json.loads(run("gh", "api", f"repos/{{owner}}/{{repo}}/commits/{sha}/pulls"))
        pr = next((p for p in pulls if p.get("merged_at") and p["base"]["ref"] == "main"), None)
        listed.append({
            "sha": short,
            "subject": subject,
            "files": run("git", "show", "--format=", "--name-only", sha).splitlines(),
            "pr": pr and {"number": pr["number"], "title": pr["title"], "url": pr["html_url"], "body": pr["body"] or ""},
        })
    print(json.dumps({"last_tag": tag, "commits": listed}, indent=2))
    if not listed:
        print(f"\nnothing on main since {tag}", file=sys.stderr)


def next_version(last, kinds, override):
    major, minor, patch = parse(last)
    derived = f"{major}.{minor + 1}.0" if "feature" in kinds else f"{major}.{minor}.{patch + 1}"
    if override is None:
        return derived
    if parse(override) <= parse(last):
        fail(f"{override} is not after {last}")
    return override


def load_release(shas):
    if not RELEASE.exists():
        fail(f"write {RELEASE.relative_to(ROOT)} first")
    r = json.loads(RELEASE.read_text())
    kinds = r.get("kinds", {})
    if set(kinds) != shas:
        missing, extra = sorted(shas - set(kinds)), sorted(set(kinds) - shas)
        fail(f"kinds must name every commit since the last tag exactly; missing {missing}, unknown {extra}")
    bad = {s: k for s, k in kinds.items() if k not in KINDS}
    if bad:
        fail(f"kinds must be one of {KINDS}: {bad}")
    summary, changes = r.get("summary", "").strip(), r.get("changes", [])
    if not summary or "\n" in summary:
        fail("summary must be one non-empty paragraph on one line")
    if not changes or not all(isinstance(c, str) and c.strip() for c in changes):
        fail("changes must be a non-empty list of bullet texts")
    return summary, [c.strip() for c in changes], set(kinds.values())


def bump(version):
    for path, prefix in (
        (SWIFT_VERSION, r'public static let version = "'),
        (PLIST, r"<key>CFBundleShortVersionString</key>\s*<string>"),
        (PLIST, r"<key>CFBundleVersion</key>\s*<string>"),
    ):
        text, n = re.subn(f"({prefix})[^\"<]+", rf"\g<1>{version}", path.read_text())
        if n != 1:
            fail(f"expected one version in {path.relative_to(ROOT)}, found {n}")
        path.write_text(text)


def restore():
    run("git", "checkout", "--", str(SWIFT_VERSION), str(PLIST))


def check_zip(zipped, version):
    """Unzips the asset as a user would and checks it is a signed arm64 app of this version."""
    with tempfile.TemporaryDirectory() as tmp:
        run("ditto", "-x", "-k", str(zipped), tmp)
        app = Path(tmp) / "ClawBar.app"
        run("codesign", "--verify", "--strict", "--deep", str(app))
        binary = app / "Contents" / "MacOS" / "ClawBar"
        if "arm64" not in run("lipo", "-archs", str(binary)).split():
            fail("the binary has no arm64 slice")
        if run(str(binary), "--version") != f"ClawBar v{version}":
            fail(f"the zipped binary does not report v{version}")


def prepare(override):
    on_synced_main()
    tag, commits = since_tag()
    summary, changes, kinds = load_release({short for short, _, _ in commits})
    if kinds <= {"internal"}:
        fail("every commit is internal: nothing to release")
    version = next_version(tag[1:], kinds, override)
    if run("git", "tag", "--list", f"v{version}"):
        fail(f"tag v{version} already exists")

    bump(version)
    zipped = zip_path(version)
    try:
        step("swift", "test")
        step("scripts/build-app.sh")
        zipped.unlink(missing_ok=True)
        # No resource forks or extended attributes: the bundle's signature lives in its files.
        run("ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", str(APP), str(zipped))
        check_zip(zipped, version)
    except SystemExit as e:
        restore()
        sys.exit(f"{e.code}; the version bump was undone")
    except BaseException:
        restore()
        raise

    bullets = "\n".join(f"- {c}" for c in changes)
    NOTES.write_text(f"{summary}\n\n## Changes\n\n{bullets}\n\n" + INSTALL.read_text().replace("{version}", version))
    run("git", "commit", "--quiet", "-m", f"Release {version}", "--", str(SWIFT_VERSION), str(PLIST))
    run("git", "tag", f"v{version}")
    print(json.dumps({"version": version, "tag": f"v{version}", "zip": str(zipped), "notes": str(NOTES)}, indent=2))


def prepared():
    """The version of the release commit at HEAD on a clean main, and whether it is pushed yet."""
    on_clean_main()
    run("git", "fetch", "--quiet", "origin")
    version = current_version()
    head = run("git", "rev-parse", "HEAD")
    if run("git", "log", "-1", "--format=%s") != f"Release {version}":
        fail(f"HEAD is not the Release {version} commit")
    if run("git", "rev-parse", f"v{version}^{{commit}}", check=False) != head:
        fail(f"tag v{version} does not point at HEAD")
    origin = run("git", "rev-parse", "origin/main")
    if origin == head:
        return version, True
    if run("git", "rev-parse", "HEAD^") != origin:
        fail("the release commit does not sit directly on origin/main")
    return version, False


def publish():
    version, pushed = prepared()
    zipped = zip_path(version)
    if not zipped.exists() or not NOTES.exists():
        fail("the zip or the notes are missing")
    if not pushed:
        run("git", "push", "--atomic", "origin", "main", f"v{version}")
    # A rerun after the push went through but the release did not.
    existing = run("gh", "release", "view", f"v{version}", "--json", "url", "-q", ".url", check=False)
    url = existing or run("gh", "release", "create", f"v{version}", str(zipped),
                          "--title", f"ClawBar {version}", "--notes-file", str(NOTES), "--verify-tag")
    print(url)


def abort():
    version, pushed = prepared()
    if pushed:
        fail(f"v{version} is already pushed; a published release is not undone here")
    run("git", "tag", "-d", f"v{version}")
    run("git", "reset", "--hard", "--quiet", "origin/main")
    # release.json stays, so a corrected one can be prepared again.
    NOTES.unlink(missing_ok=True)
    zip_path(version).unlink(missing_ok=True)
    print(f"dropped the unpushed Release {version} commit and tag v{version}")


def main(argv):
    if argv[:1] == ["plan"] and len(argv) == 1:
        plan()
    elif argv[:1] == ["prepare"] and len(argv) in (1, 2):
        prepare(argv[1] if len(argv) == 2 else None)
    elif argv == ["publish"]:
        publish()
    elif argv == ["abort"]:
        abort()
    else:
        sys.exit("usage: release.py plan | prepare [X.Y.Z] | publish | abort")


if __name__ == "__main__":
    main(sys.argv[1:])
