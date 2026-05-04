#!/usr/bin/env bash
# bump_version.sh — Bump version in pubspec.yaml, commit, tag, push.
# Pushing the tag triggers release.yml in GitHub Actions.
#
# Usage:
#   ./scripts/bump_version.sh patch        # 1.0.0+1  → 1.0.1+2
#   ./scripts/bump_version.sh minor        # 1.0.1+2  → 1.1.0+3
#   ./scripts/bump_version.sh major        # 1.1.0+3  → 2.0.0+4
#   ./scripts/bump_version.sh 1.2.3        # explicit version
#   ./scripts/bump_version.sh 1.2.3+42     # explicit version+build

set -euo pipefail

# Repository root = directory containing pubspec.yaml
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"

CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | tr -d ' \r\n')
SEMVER=$(echo "$CURRENT" | cut -d'+' -f1)
BUILD=$(echo "$CURRENT"  | grep '+' | cut -d'+' -f2 || echo "0")
IFS='.' read -r MAJOR MINOR PATCH <<< "$SEMVER"

echo "Current: $CURRENT"
NEW_BUILD=$((BUILD + 1))

case "${1:-patch}" in
  patch)   NEW_SEMVER="$MAJOR.$MINOR.$((PATCH+1))" ;;
  minor)   NEW_SEMVER="$MAJOR.$((MINOR+1)).0" ;;
  major)   NEW_SEMVER="$((MAJOR+1)).0.0" ;;
  *+*)     NEW_SEMVER=$(echo "${1}" | cut -d'+' -f1)
           NEW_BUILD=$(echo "${1}" | cut -d'+' -f2) ;;
  [0-9]*)  NEW_SEMVER="${1}" ;;
  *)       echo "Usage: $0 [patch|minor|major|X.Y.Z|X.Y.Z+N]"; exit 1 ;;
esac

NEW_VERSION="${NEW_SEMVER}+${NEW_BUILD}"
TAG="v${NEW_SEMVER}"
echo "New:     $NEW_VERSION  (tag: $TAG)"
read -r -p "Proceed? [y/N] " C
[[ "$C" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# Update pubspec.yaml
if [[ "$OSTYPE" == darwin* ]]; then
  sed -i '' "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
else
  sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
fi
echo "✅ pubspec.yaml → version: $NEW_VERSION"

# Verify
UPDATED=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | tr -d ' \r\n')
[ "$UPDATED" = "$NEW_VERSION" ] || { echo "❌ Verify failed: $UPDATED"; exit 1; }

# Commit + tag
cd "$ROOT"
git add pubspec.yaml
git commit -m "chore: bump version to $NEW_VERSION"
git tag -a "$TAG" -m "Release $TAG"
echo "✅ Commit + tag $TAG"

read -r -p "Push now? [y/N] " P
if [[ "$P" =~ ^[Yy]$ ]]; then
  git push origin HEAD
  git push origin "$TAG"
  REMOTE=$(git remote get-url origin | sed 's/\.git$//')
  echo "🚀 Pushed! Watch: $REMOTE/actions"
  echo "   Release: $REMOTE/releases"
fi
