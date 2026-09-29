# Release checks

## 0.2.0

```sh
python3 -m unittest discover -s tests -v
node --test tests/*.js
omarchy plugin validate .
git diff --check
```

Local checks cover 80 Python regression tests, both JavaScript test files,
and the plugin manifest. Standalone qmllint found no syntax errors but could
not fully resolve the shell imports, so it is not a clean QML lint result.
GitHub Actions runs Python checks on 3.10 and 3.14
and runs the JavaScript checks with Node 22.

Before calling a release fully desktop-tested, check the popup, preset switching,
pause/resume, restore conflict actions, login autostart, multiple monitors,
vertical bars, and plugin disable/re-enable on the target Omarchy release.
Unit and manifest checks do not establish those results.

Keep manifest versions and release tags aligned. Commit the complete plugin,
including LayoutState.js, its tests, and documentation, before pushing.
Publish release notes from CHANGELOG.md.

The existing marketplace listing is updated through a verification request:
choose **Verify and publish a newer upstream commit**, provide the plugin ID,
repository URL, and full current HEAD SHA. Wait for exact-commit checks and
marketplace maintainer approval. Do not open another initial plugin submission.

`publish.sh` is the legacy initial-submission script; do not use it for updates.
