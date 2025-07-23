# setup_user.sh

A flexible script to bootstrap a non-root user with sudo privileges,
secure SSH configuration, optional SSH keys, and basic hardening.

## Features

- **Idempotent & Dry-run**: Safely re-run; preview actions with `--dry-run`.
- **Config File Support**: Load parameters from a shell-style config file.
- **Interactive Prompts**: Script will prompt for all settings (username, password, SSH keys path, SSH port, log file), enabling one‑liner invocation via `bash -c "$(curl …)"`.
- **CLI Flags**: Optional flags for full automation (`--username`, `--password`, `--ssh-keys`, `--ssh-port`, etc.).
- **Logging & Error Handling**: Logs to `/var/log/setup_user.log` (customizable).
- **Distro Agnostic**: Supports Debian/Ubuntu (`apt-get`), RHEL/CentOS (`yum`/`dnf`), Alpine (`apk`).
- **SSH Hardening**: Disables root login and password auth, custom SSH port.
- **Optional fail2ban**: Installs and enables fail2ban if available.
- **ShellCheck & BATS Tests**: Includes CI workflow for linting and unit tests.

## Usage

```bash
### Make executable & run interactive mode
chmod +x setup_user.sh
# This will guide you through all required options interactively
sudo ./setup_user.sh

# Dry-run preview
sudo ./setup_user.sh --dry-run --username alice --ssh-port 2222

# Non-interactive via CLI
sudo ./setup_user.sh \
  --username alice --password 'Secret123!' \
  --ssh-keys /path/to/keys.pub \
  --ssh-port 2222 \
  --log-file /tmp/setup.log

## Quick Install from GitHub

You can run the script directly without cloning this repo. Replace `<user>` and `<repo>` with your GitHub account and repository name:

```bash
# Download and run interactively:
bash -c "$(curl -fsSL https://raw.githubusercontent.com/PTX-AG/Sudoers/main/setup_user.sh)"

# Or pull config example then run:
curl -fsSL \
  https://raw.githubusercontent.com/PTX-AG/Sudoers/main/setup_user.conf.example \
  -o setup_user.conf
bash -c "$(curl -fsSL https://raw.githubusercontent.com/PTX-AG/Sudoers/main/setup_user.sh)" \
  --config setup_user.conf
```

```bash
# Using a config file
sudo ./setup_user.sh --config setup_user.conf.example
```

## Disclaimer

This script is provided "as is", without warranty of any kind. Use at your own risk. The author is not responsible for any damage or loss resulting from its use.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Configuration File

`setup_user.conf.example` shows supported variables:

```bash
# setup_user.conf.example
USERNAME=alice
PASSWORD=Secret123!
SSH_KEYS_FILE=/home/alice/keys.pub
SSH_PORT=2222
LOG_FILE=/tmp/setup.log
DRY_RUN=false
```

## Testing & CI

An automated CI workflow runs ShellCheck and BATS tests on each push/PR. To run locally:

```bash
# ShellCheck lint
shellcheck setup_user.sh

# BATS tests
bats tests/setup_user.bats
```
