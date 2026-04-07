# Personal Development Environment

This repository contains the configuration files, automation scripts, and environment setups for my personal development machine.

## Structure

- **`dotfiles/`**: Standard configuration files for bash (`.bash_profile`, `.bashrc`, `.bash_prompt`), environment variables (`.exports`, `.path`, `.aliases`), git (`.gitconfig`, `.gitignore`), vim (`.vimrc`), tig (`.tigrc`), and editorconfig (`.editorconfig`). Symlink those files to the user directory.
- **`macos/`**: macOS-specific setup and automation.
  - `init.sh`: Initial macOS system configuration script.
  - `apps/`: Scripts to install specific applications (e.g. OpenAI on-device app, LlamaWatch).
  - `brew/`: Contains the `Brewfile` to install all necessary packages, casks, and Mac App Store apps (via `mas`). Use it with `brew bundle`.
  - `terminal/`: Contains macOS Terminal profile configurations (e.g., `mk.terminal`).
  - `automation/`
    - `shortcuts/`: Scripts for macOS Shortcuts. Create proper Shortcuts through the Shortcuts app and add `Run Shell Script` actions, executing those shell scripts.
    - `launchd/`: Symlink Launchd configs to `~/Library/LaunchAgents`.<br />Start a service by calling `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$SERVICE.plist`.<br />Stop a service by calling `launchctl bootout gui/$(id -u)/$SERVICE`.
- **`opencode/`**: Configuration for [OpenCode](https://opencode.ai/).
  - Includes custom providers setup (Google Gemini & local Ollama models).
  - Configures custom agents and permissions (`agents/`).
  - Configuration files (`opencode.jsonc`, `dcp.jsonc`, `tui.json`).
- **`ollama/`**: Local LLM setup and model configurations (e.g., using `qwen2.5:0.5b` for tiny background tasks).
- **`colima/`**: Configurations for Colima profiles (Docker, Containerd, AI).
- **`direnv/`**: Configuration for `direnv` (`direnv.toml`).

## Setup Instructions

### First setup

Execute `macos/init.sh` once to setup your mac.

### Dotfiles

Symlink the dotfiles to your home directory:

```bash
find "$(pwd)/dotfiles" -maxdepth 1 -name ".*" -exec ln -sf {} "$HOME" \;
ln -s $(pwd)/direnv ~/.config/
```

### OpenCode (AI Agent harness)

Symlink the opencode directory to the global configs:

```bash
ln -s $(pwd)/opencode ~/.config/opencode
```

Ensure your API keys (e.g., for Google Gemini) are securely configured in your local environment, as they are excluded from this repository.

### Launchd Services

The `macos/automation/launchd/` directory contains background services (agents) that can be managed via macOS `launchd`.

Available Agents:
- `com.user.opencode-serve`: Runs `opencode serve` to keep the OpenCode server running in the background as a proper macOS service.
- `com.user.opencode-restartonchange`: Watches for changes to the `opencode` binary or configuration files and automatically restarts the OpenCode server when an update occurs.

Link the configuration files to your user's LaunchAgents directory:

```bash
ln -s $(pwd)/macos/automation/launchd/com.user.opencode-serve.plist ~/Library/LaunchAgents/
ln -s $(pwd)/macos/automation/launchd/com.user.opencode-restartonchange.plist ~/Library/LaunchAgents/
```

Start a service by bootstrapping its configuration file:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.opencode-serve.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.opencode-restartonchange.plist
```

Stop a service by using bootout with the service label:

```bash
launchctl bootout gui/$(id -u)/com.user.opencode-serve
launchctl bootout gui/$(id -u)/com.user.opencode-restartonchange
```

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

### Colima

Provides container environment for docker and nerdctl.

Configures the following virtual machines (profiles):
- `docker`: Machine for docker environment, accessible through `docker`
- `containerd`: Bare containers, accessible through `nerdctl`
- `ai`: krunkit environment to run LLMs

No VM is started by default. Start a profile with `colima start <profile>`.

Perform the following for installation:
```bash
ln -s $(pwd)/colima ~/.colima

colima completion bash > /usr/local/etc/bash_completion.d/colima
colima -p containerd nerdctl install
```

## Things others would have to adjust

- Full path containing my username `mkuckert`, e.g. in `macos/automation/launchd/com.user.opencode-serve.plist`
- My user id `422624326` as used in launchd services, e.g. in `macos/automation/launchd/com.user.opencode-restartonchange.plist`

## Source

Most is my own work.

Some of the `dotfiles` are inspired from [Mathias Bynens](https://github.com/mathiasbynens/dotfiles) but heavily modified to match my preferences.
