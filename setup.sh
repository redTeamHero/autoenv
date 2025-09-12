#!/usr/bin/env bash
# ============================
# Setup Python Virtual Env
# ============================

ENV_NAME=${1:-venv}
PROJECT_DIR=$(pwd)

echo ">>> Creating virtual environment: $ENV_NAME"

python3 -m venv "$ENV_NAME"

echo ">>> Activating..."
source "$ENV_NAME/bin/activate"

echo ">>> Upgrading pip..."
pip install --upgrade pip

if [ -f "requirements.txt" ]; then
    echo ">>> Installing dependencies from requirements.txt..."
    pip install -r requirements.txt
else
    echo ">>> No requirements.txt found. You can install packages manually with pip."
fi

# ============================
# Add auto-activation + auto-deactivation
# ============================
SHELL_RC="$HOME/.bashrc"
[ -n "$ZSH_VERSION" ] && SHELL_RC="$HOME/.zshrc"

HOOK_CODE="
# >>> Auto-manage venv for $PROJECT_DIR >>>
cd_auto_venv() {
    if [ \"\$(pwd)\" = \"$PROJECT_DIR\" ]; then
        if [ -f \"$PROJECT_DIR/$ENV_NAME/bin/activate\" ]; then
            if [ -z \"\$VIRTUAL_ENV\" ] || [ \"\$VIRTUAL_ENV\" != \"$PROJECT_DIR/$ENV_NAME\" ]; then
                echo \"(Auto) Activating venv in $PROJECT_DIR...\"
                source \"$PROJECT_DIR/$ENV_NAME/bin/activate\"
            fi
        fi
    else
        if [ -n \"\$VIRTUAL_ENV\" ] && [ \"\$VIRTUAL_ENV\" = \"$PROJECT_DIR/$ENV_NAME\" ]; then
            echo \"(Auto) Deactivating venv from $PROJECT_DIR...\"
            deactivate
        fi
    fi
}
PROMPT_COMMAND=\"cd_auto_venv;\$PROMPT_COMMAND\"
# <<< Auto-manage venv for $PROJECT_DIR <<<
"

if ! grep -q "Auto-manage venv for $PROJECT_DIR" "$SHELL_RC"; then
    echo ">>> Adding auto-activation/deactivation hook to $SHELL_RC"
    echo "$HOOK_CODE" >> "$SHELL_RC"
else
    echo ">>> Auto-management already set in $SHELL_RC"
fi

echo ">>> Virtual environment setup complete!"
echo ">>> Restart your terminal or run: source $SHELL_RC"
