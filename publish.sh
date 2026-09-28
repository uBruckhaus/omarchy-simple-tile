#!/usr/bin/env bash
# Automated Publisher for Simple Tile
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

echo "=== Simple Tile: Marketplace Publisher ==="

# Check gh authentication
if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated yet."
    echo "Starting authentication..."
    gh auth login -h github.com -p https --web
fi

GH_USER="$(gh api user --jq .login 2>/dev/null || true)"
if [[ -z "$GH_USER" ]]; then
    echo "Error: Could not retrieve GitHub username."
    exit 1
fi

echo "Authenticated as: $GH_USER"
REPO_NAME="omarchy-simple-tile"
REPO_URL="https://github.com/$GH_USER/$REPO_NAME"

# Check if remote already exists
if ! git remote get-url origin >/dev/null 2>&1; then
    echo "Creating public repository: $REPO_NAME..."
    gh repo create "$REPO_NAME" --public --source=. --remote=origin --push || {
        echo "Adding remote and pushing..."
        git remote add origin "$REPO_URL.git" || true
        git push -u origin main
    }
else
    echo "Pushing latest commits to origin..."
    git push -u origin main
fi

echo "Repository published to: $REPO_URL"

# Generate issue body for marketplace submission
SUBMISSION_FILE="$(mktemp /tmp/marketplace-submission-XXXXXX.md)"
cat << EOF > "$SUBMISSION_FILE"
### Repository URL

$REPO_URL

### Category

Desktop

### Tags

Workspaces, Hyprland, Bar

### Maintainer notes

Calm, per-workspace window limits and automatic overflow management for Omarchy. Powered by Quickshell and Python standard library. Cleanly validated via 'omarchy plugin validate'. Includes preview.png.

Startup and runtime architecture strictly follows the approved marketplace security baseline:
- No background daemons or persistent PID files (eliminating stale PID and reuse risks).
- Event-driven one-shot execution via Quickshell's native Hyprland event listener.
- Direct argv execution of the Python helper without shell wrapping (no sh -c).
- Target window addresses strictly validated against hexadecimal format (^0x[0-9a-f]+$); target workspaces validated as positive integers.
- Serialization via user-isolated runtime file locks in \$XDG_RUNTIME_DIR.
- Hyprland commands run with explicit timeouts and direct argv vectors via subprocess.run without a shell.
- Full respect for manual moves: moving a window manually (e.g. Super+Shift+N) intentionally overrides tiling limits as intended.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
EOF

echo "Submitting to omacom/omarchy-plugin-marketplace..."
ISSUE_URL="$(gh issue create \
    --repo omacom/omarchy-plugin-marketplace \
    --title "[Plugin]: Simple Tile" \
    --body-file "$SUBMISSION_FILE")"

rm -f "$SUBMISSION_FILE"

echo ""
echo "🎉 SUCCESS! Plugin submitted to the Omarchy Marketplace!"
echo "Issue URL: $ISSUE_URL"
echo "Repository: $REPO_URL"
