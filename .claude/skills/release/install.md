## Install

Requires macOS 14 or later on Apple silicon, and [Claude Code](https://claude.ai/code) installed and logged in.

1. Download `ClawBar-{version}-arm64.zip` and unzip it.
2. Move `ClawBar.app` to `/Applications`. When updating, quit the running ClawBar from its menu first and replace the
   old app; delete any copy left in `~/Applications`.
3. The app is ad-hoc signed, not notarized, so macOS blocks the first open. Either run
   `xattr -dr com.apple.quarantine /Applications/ClawBar.app`, or open it once, then allow it under
   **System Settings → Privacy & Security → Open Anyway**.

ClawBar registers itself to open at login; untick **Launch at login** in its Settings to stop that.

To build from source instead (needs a Swift 6.2 toolchain): `scripts/build-app.sh --install`. See the README for configuration, the command line, and the differences from the original.
