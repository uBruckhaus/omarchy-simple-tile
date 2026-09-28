# Release checks

## Verified locally for 0.1.0

- 17 Python regression tests pass.
- The installed Omarchy manifest validator accepts the plugin.
- The QML entry point loads in an isolated Quickshell session.
- The installed popup renders in the current desktop theme.
- A live three-window test confirmed the exact-cap boundary, overflow to the next
  workspace, follow behavior, and preservation of the existing window.

## Before broader distribution

- Run `python3 -m unittest discover -s tests -v`.
- Run `omarchy plugin validate .` on the target Omarchy release.
- Load the widget in Quickshell and open its popup.
- Check pause/resume, all eight limits, follow/stay, persistence, and theme changes.
- Open three test windows at a limit of two; confirm only the third overflows.
- Check two physical monitors, vertical bars, named workspaces, and monitor rules.
- Test plugin disable, re-enable, shell restart, and update.
- Capture a screenshot of the popup for a marketplace submission.
- Review the marketplace's submission requirements when submitting. This repository
  is an installable plugin, not a claim of marketplace acceptance.

Keep the manifest version in step with release tags. GitHub Actions tests the
Python behavior and manifest structure; desktop integration needs Omarchy.
