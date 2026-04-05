# Personal Development Environment

This repository contains the configuration files, automation scripts, and environment setups for my personal development machine.

## Structure

- **`dotfiles/`**: Standard configuration files for bash (`.bash_profile`, `.profile`), git (`.gitconfig`), vim (`.vimrc`), and tig (`.tigrc`). Symlink those files to the user directory
- **`macos/`**: macOS-specific setup and automation.
  - `brew/`: Contains the `Brewfile` to install all necessary packages, casks, and Mac App Store apps (via `mas`). Use it with `brew bundle`
  - `automation/`
  - Scripts for macOS Shortcuts. Create proper Shortcuts through the Shortcuts app and add `Run Shell Script` actions, executing those shell scripts
  - Symlink Launchd configs to `~/Library/LaunchAgents`.<br />Start a service by calling `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$SERVICE.plist`.<br />Stop a service by calling `launchctl bootout gui/$(id -u)/$SERVICE`
- **`opencode/`**: Configuration for [OpenCode](https://opencode.ai/).
  - Includes custom providers setup (Google Gemini & local Ollama models).
  - Configures custom agents and permissions.
  - Plugin and dependency definitions (`package.json`, `opencode.jsonc`, `dcp.jsonc`).
- **`ollama/`**: Local LLM setup and model configurations (e.g., using `qwen2.5:0.5b` for tiny background tasks).

## Setup Instructions

### First setup

Execute `dotfiles/.macos` once to setup your mac.

### Dotfiles

Symlink the dotfiles to your home directory:

```bash
find "$(pwd)/dotfiles" -maxdepth 1 -name ".*" -exec ln -sf {} "$HOME" \;
ln -s $(pwd)/direnv ~/.config/
```

### OpenCode (AI Agent harness)

Symlink the opencode directory to the global configs:

```bash
ln -s $(pwd)/opencode ~/.config/
```

Ensure your API keys (e.g., for Google Gemini) are securely configured in your local environment, as they are excluded from this repository.

### Homebrew

To install all required system packages, CLI tools, and applications:

```bash
cd macos/brew
brew bundle

BREW_PREFIX=$(brew --prefix)
ln -s "${BREW_PREFIX}/bin/gsha256sum" "${BREW_PREFIX}/bin/sha256sum"

# Install brews installed bash as shell for current user
if ! fgrep -q "${BREW_PREFIX}/bin/bash" /etc/shells; then
  echo "${BREW_PREFIX}/bin/bash" | sudo tee -a /etc/shells;
  chsh -s "${BREW_PREFIX}/bin/bash";
fi;

# Start automatic updates every 12 hours, immediatelly and on system boot if on AC power.
# Passes --sudo as well to enable upgrading casks. The updater may ask for a password.
brew autoupdate start 43200 --immediate --upgrade --cleanup --ac-only --sudo
```

### Ollama (local LLMs)

Brew starts the local Ollama service. You can pull required models, e.g. those configured in `opencode.jsonc` by calling `ollama run <model>`.

Or build the models from a Modelfile:
```bash
ollama create tiny -f ollama/models/Modelfile.tiny
```

## Source

Most is my own work.

Some of the `dotfiles` are inspired from [Mathias Bynens](https://github.com/mathiasbynens/dotfiles) but heavily modified to match my preferences.
