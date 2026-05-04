#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bump_version.sh
#
# Bumps the version in pubspec.yaml, creates a git commit and tag,
# then pushes — which triggers the GitHub Actions release workflow.
#
# Usage:
#   ./scripts/bump_version.sh patch          # 1.0.0+1 → 1.0.1+2
#   ./scripts/bump_version.sh minor          # 1.0.1+2 → 1.1.0+3
#   ./scripts/bump_version.sh major          # 1.1.0+3 → 2.0.0+4
#   ./scripts/bump_version.sh 1.2.3          # explicit version, auto build+N
#   ./scripts/bump_version.sh 1.2.3+42       # explicit version+build
#
# After running, GitHub Actions release.yml will:
#   1. Build Android APK/AAB + iOS IPA in parallel
#   2. Create a GitHub Release with all artifacts
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBSPEC="$ROOT_DIR/pubspec.yaml"

# ── Read current version ──────────────────────────────────────────────────────
CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | tr -d ' \r\n')
CURRENT_SEMVER=$(echo "$CURRENT" | cut -d'+' -f1)
CURRENT_BUILD=$(echo "$CURRENT" | cut -d'+' -f2)
if [ "$CURRENT_SEMVER" = "$CURRENT_BUILD" ]; then CURRENT_BUILD=0; fi  # no build number

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_SEMVER"

echo "Current version: $CURRENT (semver=$CURRENT_SEMVER, build=$CURRENT_BUILD)"

# ── Calculate new version ─────────────────────────────────────────────────────
ARG="${1:-patch}"
NEW_BUILD=$((CURRENT_BUILD + 1))

case "$ARG" in
  patch)
    NEW_SEMVER="$MAJOR.$MINOR.$((PATCH + 1))"
    ;;
  minor)
    NEW_SEMVER="$MAJOR.$((MINOR + 1)).0"
    ;;
  major)
    NEW_SEMVER="$((MAJOR + 1)).0.0"
    ;;
  *+*)
    # Explicit "1.2.3+42"
    NEW_SEMVER=$(echo "$ARG" | cut -d'+' -f1)
    NEW_BUILD=$(echo "$ARG" | cut -d'+' -f2)
    ;;
  [0-9]*)
    # Explicit semver "1.2.3" — auto-increment build
    NEW_SEMVER="$ARG"
    ;;
  *)
    echo "❌ Unknown bump type: $ARG"
    echo "   Usage: $0 [patch|minor|major|X.Y.Z|X.Y.Z+N]"
    exit 1
    ;;
esac

NEW_VERSION="${NEW_SEMVER}+${NEW_BUILD}"
TAG="v${NEW_SEMVER}"

echo "New version:     $NEW_VERSION"
echo "Git tag:         $TAG"
echo ""

# ── Confirm ──────────────────────────────────────────────────────────────────
read -r -p "Proceed? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ── Update pubspec.yaml ───────────────────────────────────────────────────────
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
else
  sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
fi

echo "✅ Updated pubspec.yaml: version: $NEW_VERSION"

# ── Verify ────────────────────────────────────────────────────────────────────
UPDATED=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | tr -d ' \r\n')
if [ "$UPDATED" != "$NEW_VERSION" ]; then
  echo "❌ pubspec.yaml update failed! Got: $UPDATED"
  exit 1
fi

# ── Git commit + tag ──────────────────────────────────────────────────────────
cd "$ROOT_DIR"

git add pubspec.yaml
git commit -m "chore: bump version to $NEW_VERSION"

git tag -a "$TAG" -m "Release $TAG"

echo ""
echo "✅ Created commit and tag $TAG"
echo ""
echo "Push to trigger GitHub Actions release:"
echo "  git push origin main && git push origin $TAG"
echo ""
read -r -p "Push now? [y/N] " PUSH_CONFIRM
if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  git push origin main
  git push origin "$TAG"
  echo ""
  echo "🚀 Pushed! Monitor the release at:"
  REMOTE=$(git remote get-url origin | sed 's/\.git$//')
  echo "   $REMOTE/actions"
  echo "   $REMOTE/releases"
fi
