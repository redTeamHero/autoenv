#!/usr/bin/env bash
# ============================================
# Setup Python Virtual Env (+ safe rename + auto activate/deactivate)
# Usage:
#   ./setup_venv.sh                          # run inside project (env name: venv)
#   ./setup_venv.sh /path/to/project         # from anywhere (env: venv)
#   ./setup_venv.sh /path/to/project .venv   # custom env name
#   ./setup_venv.sh uninstall                # remove the auto-activate hook from your shell RC
#
# Notes:
# - To exit a virtualenv at any time: `deactivate`
# - Avoid `pip --user` inside a venv (it will fail).
# ============================================

set -euo pipefail

# --- Uninstall mode: remove the hook from ~/.bashrc or ~/.zshrc by marker ---
if [[ "${1:-}" == "uninstall" ]]; then
  # Pick the right RC
  SHELL_RC="$HOME/.bashrc"
  [[ -n "${ZSH_VERSION-}" ]] && SHELL_RC="$HOME/.zshrc"
  [[ ! -f "$SHELL_RC" ]] && { echo "No $SHELL_RC found."; exit 0; }

  # Remove any blocks between our markers
  if grep -q "Auto-manage venv \[" "$SHELL_RC"; then
    tmp="$(mktemp)"
    # Delete every block bounded by our markers
    awk '
      BEGIN{skip=0}
      /# >>> Auto-manage venv \[/ {skip=1}
      skip==0 {print}
      /# <<< Auto-manage venv \[/ {skip=0}
    ' "$SHELL_RC" > "$tmp"
    mv "$tmp" "$SHELL_RC"
    echo "Removed auto-activate hooks from $SHELL_RC"
    echo "Reload your shell: source \"$SHELL_RC\""
  else
    echo "No auto-activate hooks found in $SHELL_RC"
  fi
  exit 0
fi

# -------- Args --------
PROJECT_DIR="${1:-$PWD}"
ENV_NAME="${2:-venv}"

# -------- Realpath (portable) --------
if command -v realpath >/dev/null 2>&1; then
  PROJECT_DIR="$(realpath "$PROJECT_DIR")"
else
  case "$PROJECT_DIR" in
    /*) : ;;
    *)  PROJECT_DIR="$PWD/$PROJECT_DIR" ;;
  esac
fi

# -------- Ensure project dir exists --------
mkdir -p "$PROJECT_DIR"

# -------- Sanitize dirname (replace unsafe chars with _) --------
orig_dirname="$(basename "$PROJECT_DIR")"
parent_dir="$(dirname "$PROJECT_DIR")"
safe_dirname="$(printf "%s" "$orig_dirname" | sed -E 's/[^A-Za-z0-9._-]+/_/g')"

if [ "$safe_dirname" != "$orig_dirname" ]; then
  echo ">>> Renaming project folder:"
  echo "    '$orig_dirname'  ->  '$safe_dirname'"
  mv "$PROJECT_DIR" "$parent_dir/$safe_dirname"
  PROJECT_DIR="$parent_dir/$safe_dirname"

  # If we were *in* that directory, move our shell there too (robust check)
  if [ "$(pwd -P)" = "$parent_dir/$orig_dirname" ]; then
    cd "$PROJECT_DIR"
  fi
fi

echo ">>> Project: $PROJECT_DIR"
echo ">>> Env:     $ENV_NAME"

# -------- Create venv --------
cd "$PROJECT_DIR"
if [ ! -d "$ENV_NAME" ]; then
  echo ">>> Creating virtual environment..."
  python3 -m venv "$ENV_NAME"
else
  echo ">>> Virtual environment already exists — skipping create."
fi

# -------- One-time activation for setup --------
echo ">>> Activating (one-time for setup)..."
# shellcheck disable=SC1090
source "$ENV_NAME/bin/activate"

# -------- Pip + requirements --------
echo ">>> Upgrading pip..."
# Avoid any odd user-install bleed; inside venv this is safe and isolated
pip install --upgrade pip

if [ -f "requirements.txt" ]; then
  echo ">>> Installing dependencies from requirements.txt..."
  # No --user here (it breaks in venv)
  pip install -r requirements.txt
else
  echo ">>> No requirements.txt found — skipping dependency install."
fi

# -------- Pick shell rc --------
SHELL_RC="$HOME/.bashrc"
if [ -n "${ZSH_VERSION-}" ]; then
  SHELL_RC="$HOME/.zshrc"
fi
touch "$SHELL_RC"

# -------- Unique hook id from path hash --------
hash_id="$(
  { command -v md5sum >/dev/null && printf "%s" "$PROJECT_DIR" | md5sum | awk '{print $1}'; } || \
  { command -v md5    >/dev/null && md5 -q -s "$PROJECT_DIR"; } || \
  { command -v shasum >/dev/null && printf "%s" "$PROJECT_DIR" | shasum | awk '{print $1}'; } || \
  echo "nohash"
)"

MARKER="Auto-manage venv [$hash_id]"
FUNC_NAME="cd_auto_venv_${hash_id}"

# -------- Inject hook (idempotent) --------
if ! grep -Fq "$MARKER" "$SHELL_RC"; then
  echo ">>> Adding auto-activation/deactivation hook to $SHELL_RC"
  cat >> "$SHELL_RC" <<EOF

# >>> $MARKER >>>
$FUNC_NAME() {
  local project_dir="$PROJECT_DIR"
  local env_path="\$project_dir/$ENV_NAME"

  # Are we inside the project (or any subdir)?
  case "\$PWD/" in
    "\$project_dir"/*)
      if [ -f "\$env_path/bin/activate" ]; then
        # Activate only if not already active
        if [ -z "\${VIRTUAL_ENV-}" ] || [ "\$VIRTUAL_ENV" != "\$env_path" ]; then
          echo "(auto) Activating: \$env_path"
          # shellcheck disable=SC1090
          . "\$env_path/bin/activate"
        fi
      fi
      ;;
    *)
      # If we leave the project while that env is active, deactivate it
      if [ -n "\${VIRTUAL_ENV-}" ] && [ "\$VIRTUAL_ENV" = "\$env_path" ]; then
        echo "(auto) Deactivating: \$env_path"
        deactivate
      fi
      ;;
  esac
}

# Attach to prompt loop (Zsh preferred hook, Bash PROMPT_COMMAND fallback)
if [ -n "\${ZSH_VERSION-}" ]; then
  autoload -Uz add-zsh-hook 2>/dev/null || true
  if command -v add-zsh-hook >/dev/null 2>&1; then
    add-zsh-hook precmd $FUNC_NAME
  else
    if [ -n "\${PROMPT_COMMAND-}" ]; then
      PROMPT_COMMAND="$FUNC_NAME;\$PROMPT_COMMAND"
    else
      PROMPT_COMMAND="$FUNC_NAME"
    fi
  fi
else
  if [ -n "\${PROMPT_COMMAND-}" ]; then
    PROMPT_COMMAND="$FUNC_NAME;\$PROMPT_COMMAND"
  else
    PROMPT_COMMAND="$FUNC_NAME"
  fi
fi
# <<< $MARKER <<<
EOF
else
  echo ">>> Hook already present — skipping."
fi

echo ">>> Done!"
echo ">>> Reload your shell to enable auto-manage:"
if [ -n "${ZSH_VERSION-}" ]; then
  echo "    source ~/.zshrc"
else
  echo "    source ~/.bashrc"
fi

echo ">>> Test:"
echo "    cd ~ && cd \"$PROJECT_DIR\"    # auto-activate"
echo "    cd ~                           # auto-deactivate"
