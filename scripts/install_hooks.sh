#!/bin/sh
# Opt-in: install a pre-commit hook that runs the privacy scan on staged
# changes (scripts/pii_scan.py). Remove with: rm .git/hooks/pre-commit
set -e
ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/.git/hooks/pre-commit"
if [ -e "$HOOK" ] && ! grep -q "pii_scan.py" "$HOOK"; then
  echo "A different pre-commit hook already exists at $HOOK; add this line to it instead:"
  echo '  python3 "$(git rev-parse --show-toplevel)/scripts/pii_scan.py" || exit 1'
  exit 1
fi
cat > "$HOOK" <<'HOOK'
#!/bin/sh
# Installed by scripts/install_hooks.sh: blocks household details in commits.
python3 "$(git rev-parse --show-toplevel)/scripts/pii_scan.py" || exit 1
HOOK
chmod +x "$HOOK"
echo "Installed $HOOK"
