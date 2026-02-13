#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root no matter where script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Not inside a git repo."
  exit 1
fi

remote="origin"
dev_branch="dev"
main_branch="main"

# If set to YES, bypass the interactive spam prompt.
confirm_env="${RS_CONFIRM_SPAM:-}"

orig_branch="$(git rev-parse --abbrev-ref HEAD)"

echo "== RatedStats: Promote ${dev_branch} -> ${main_branch} (full merge; tag main) =="

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Working tree is dirty. Commit/stash first."
  git status --porcelain
  exit 1
fi

next_main_tag() {
  # RatedStats main tag pattern:
  #   v<major>.<build>
  # Examples seen in published artifacts: v1.22, v2.02
  #
  # We intentionally IGNORE beta tags (vX.Y-beta) and anything with extra suffixes.
  local max_major=-1
  local max_build=-1
  local t major build

  while IFS= read -r t; do
    if [[ "$t" =~ ^v([0-9]+)\.([0-9]+)$ ]]; then
      major=$((10#${BASH_REMATCH[1]}))
      build=$((10#${BASH_REMATCH[2]}))

      if (( major > max_major )); then
        max_major="$major"
        max_build="$build"
      elif (( major == max_major && build > max_build )); then
        max_build="$build"
      fi
    fi
  done < <(git tag --list 'v*' | tr -d '\r')

  if (( max_major < 0 || max_build < 0 )); then
    echo "ERROR: Could not find any existing main tags matching v<major>.<build>"
    echo "       This script refuses to invent a scheme."
    return 1
  fi

  local next_build=$((max_build + 1))
  local candidate="v${max_major}.${next_build}"

  while git rev-parse -q --verify "refs/tags/${candidate}" >/dev/null; do
    next_build=$((next_build + 1))
    candidate="v${max_major}.${next_build}"
  done

  printf '%s\n' "${candidate}"
}

echo "[1/8] Fetching ${remote} (including tags)..."
git fetch --prune --tags "${remote}"

for b in "${dev_branch}" "${main_branch}"; do
  if ! git show-ref --verify --quiet "refs/heads/${b}"; then
    echo "ERROR: Local branch '${b}' not found."
    echo "Fix: git checkout -b ${b} ${remote}/${b}"
    exit 1
  fi
done

echo "[2/8] Fast-forwarding local branches..."
git checkout -q "${dev_branch}"
git pull --ff-only "${remote}" "${dev_branch}"

git checkout -q "${main_branch}"
git pull --ff-only "${remote}" "${main_branch}"

echo "[3/8] Calculating diff ${remote}/${main_branch}..${remote}/${dev_branch}..."
mapfile -t changed < <(git diff --name-only "${remote}/${main_branch}..${remote}/${dev_branch}" | tr -d '\r')
if [[ ${#changed[@]} -eq 0 ]]; then
  echo "Nothing to merge: ${dev_branch} has no changes vs ${main_branch}."
  git checkout -q "${orig_branch}"
  exit 0
fi

echo "Changed files (${#changed[@]}):"
printf ' - %s\n' "${changed[@]}"

echo
echo "[4/8] Spam scan (prints/chat/event/ticker/onupdate)..."

spam_hits=0

scan_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  case "$f" in
    *.lua|*.toc) ;;
    *) return 0 ;;
  esac

  if grep -nE \
    '(^|[^a-zA-Z0-9_])(print|DEFAULT_CHAT_FRAME:AddMessage|ChatFrame[0-9]+:AddMessage|SendChatMessage|BNSendWhisper)\s*\(|RegisterEvent\s*\(|RegisterAllEvents\s*\(|C_Timer\.NewTicker\s*\(|C_Timer\.After\s*\(|SetScript\s*\(\s*["'\'']OnUpdate["'\'']' \
    "$f" >/dev/null 2>&1; then
    echo
    echo "---- ${f} ----"
    grep -nE \
      '(^|[^a-zA-Z0-9_])(print|DEFAULT_CHAT_FRAME:AddMessage|ChatFrame[0-9]+:AddMessage|SendChatMessage|BNSendWhisper)\s*\(|RegisterEvent\s*\(|RegisterAllEvents\s*\(|C_Timer\.NewTicker\s*\(|C_Timer\.After\s*\(|SetScript\s*\(\s*["'\'']OnUpdate["'\'']' \
      "$f" || true
    spam_hits=1
  fi
}

for f in "${changed[@]}"; do
  scan_file "$f"
done

if [[ "${spam_hits}" -eq 1 ]]; then
  echo
  echo "WARNING: Potentially spammy changes detected above."
  if [[ "${confirm_env}" != "YES" ]]; then
    echo "Type YES to proceed (or Ctrl+C to abort):"
    read -r ans
    if [[ "${ans}" != "YES" ]]; then
      echo "Aborted."
      git checkout -q "${orig_branch}"
      exit 1
    fi
  else
    echo "RS_CONFIRM_SPAM=YES set; proceeding without prompt."
  fi
else
  echo "No spam triggers detected."
fi

echo
echo "[5/8] Merging ${dev_branch} into ${main_branch} (preserve history)..."
git checkout -q "${main_branch}"
# Pre-calc the next main tag
tag="$(next_main_tag)"
echo "Next main tag (will be stamped into TOC + used as git tag): ${tag}"
merge_msg="Release ${tag}"
echo "Merge message (enter to accept default): ${merge_msg}"
read -r user_msg || true
if [[ -n "${user_msg}" ]]; then
  merge_msg="${user_msg}"
fi

# Real merge preserving commit history
# Attempt merge
if ! git merge --no-ff "${dev_branch}" -m "${merge_msg}"; then
    echo
    echo "Merge conflict detected. Attempting auto-resolution for known safe files..."

    # Accept DEV versions for safe files
    git checkout --theirs .gitattributes 2>/dev/null || true
    git checkout --theirs .vscode/RatedStats.code-workspace 2>/dev/null || true
    git checkout --theirs RatedStats.toc 2>/dev/null || true

    # Stage resolved files
    git add .gitattributes 2>/dev/null || true
    git add -f .vscode/RatedStats.code-workspace 2>/dev/null || true
    git add RatedStats.toc 2>/dev/null || true

    # Check if any conflicts remain
    if git diff --name-only --diff-filter=U | grep -q .; then
        echo "Unresolved conflicts remain. Please resolve manually."
        exit 1
    fi

    echo "Auto-resolution complete. Finalizing merge..."
    git commit --no-edit
fi

# Stamp the release version into the root TOC and stage it (even if dev didn't touch it).
# This makes in-game version comparisons possible (Details/BGE-style peer compare).
if [[ -f "RatedStats.toc" ]]; then
  if grep -qE '^##[[:space:]]*Version:' "RatedStats.toc"; then
    if command -v perl >/dev/null 2>&1; then
      perl -pi -e "s/^##\\s*Version:\\s*.*\$/## Version: ${tag}/m" "RatedStats.toc"
    else
      sed -i "s/^##[[:space:]]*Version:.*$/## Version: ${tag}/" "RatedStats.toc"
    fi
  else
    # If Version line is missing, insert it at the top.
    { echo "## Version: ${tag}"; cat "RatedStats.toc"; } > "RatedStats.toc.tmp" && mv "RatedStats.toc.tmp" "RatedStats.toc"
  fi
  git add -- "RatedStats.toc"
else
  echo "WARN: RatedStats.toc not found; skipping TOC version stamp."
fi

if git diff --cached --quiet; then
  echo "Nothing staged after promotion. Exiting."
  git checkout -q "${orig_branch}"
  exit 0
fi

echo
echo "[5c] Committing promoted changes..."
git commit -m "${merge_msg}"

echo
echo "[6/8] Tagging main with next version (based on latest main tag)..."
echo "Tagging main: ${tag}"

# RatedStats releases commonly use lightweight tags; keep that behavior.
git tag "${tag}"

echo
echo "[7/8] Pushing ${main_branch} + tags to ${remote}..."
git push "${remote}" "${main_branch}"
git push "${remote}" --tags

echo
echo "Merge complete."
git checkout -q "${orig_branch}"

echo
echo "[8/8] Creating GitHub release..."

if command -v gh >/dev/null 2>&1; then
  gh release create "${tag}" \
    --title "RatedStats ${tag}" \
    --generate-notes
else
  echo "WARNING: GitHub CLI not installed. Release not created."
fi