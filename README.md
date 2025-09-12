chmod +x setup_venv.sh

# A) Run from inside the project
./setup_venv.sh

# B) Run from anywhere, target a project
./setup_venv.sh "/home/admin/crm/metro2 (copy 1)/crm"

# C) Custom env folder name
./setup_venv.sh "/home/admin/crm/metro2 (copy 1)/crm" .venv

# Then reload your shell once:
source ~/.bashrc   # or: source ~/.zshrc
