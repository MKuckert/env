# Personal Development Environment

This repository contains the configuration files, automation scripts, and environment setups for my personal development machine.

## Structure

- **`dotfiles/`**: Standard configuration files for bash (`.bash_profile`, `.bashrc`, `.bash_prompt`), environment variables (`.exports`, `.path`, `.aliases`), git (`.gitconfig`, `.gitconfig-work`, `.gitconfig-private`, `.gitignore`), vim (`.vimrc`), tig (`.tigrc`), editorconfig (`.editorconfig`), and environment template (`.env.example`). Symlink those files to the user directory.
- **`ssh/`**: SSH configuration files (`config`, `allowed_signers`). Symlink to `~/.ssh/`.
- **`macos/`**: macOS-specific setup and automation.
  - `init.sh`: Initial macOS system configuration script.
  - `bin/`: Build scripts for various tools.
    - `llamawatch/`: Builds [LlamaWatch](https://github.com/MKuckert/LlamaWatch) macOS app from source and installs to `/Applications`.
    - `apple-on-device-openai/`: Clones and opens the [Apple On-Device OpenAI](https://github.com/MKuckert/apple-on-device-openai) Xcode project for building.
    - `timelog/`: Builds [timelog](https://github.com/qbart/timelog) CLI tool and installs bash completion.
    - `cherri/`: Builds [Cherri](https://github.com/electrikmilk/cherri) CLI compiler (Go) for macOS Shortcuts.
  - `brew/`: Contains the `Brewfile` to install all necessary packages, casks, and Mac App Store apps (via `mas`). Use it with `brew bundle`.
  - `terminal/`: Contains macOS Terminal profile configurations (e.g., `mk.terminal`).
  - `automation/`
    - `shortcuts/`: macOS Shortcuts written in Cherri. Contains the source `.cherri` files. Use the `cherri` compiler to create the corresponding `.shortcut`s.
- **`opencode/`**: Configuration for [OpenCode](https://opencode.ai/).
  - Includes custom providers setup (Google Gemini & local Ollama models).
  - Configures custom agents and permissions (`agents/`).
  - Configuration files (`opencode.jsonc`, `dcp.jsonc`, `tui.json`).
    - Custom commands (`command/` - e.g., `tokenscope.md`).
  - MCP tools are routed through containerized agents via `docker-mcp-gateway-run.sh` (fsrw, fsro, git, web).
  - The `opencode/` directory is symlinked to `~/.config/opencode/` for global config, while `.opencode/` serves as the project-local config directory.
- **`omlx/`**: [OMLX](https://github.com/secondstate/omlx) configuration for running OpenMoE LLM models. Contains `settings.json` with server, model, memory, cache, and sampling parameters. Symlink to `~/.omlx/`.
- **`mtplx/`**: [MTPLX](https://mtplx.ai/) model serving configuration. Contains `serve.sh` for running MTPLX-optimized models (e.g., Qwen3.6-27B) with custom context and caching settings.
- **`llama.cpp/`**: Local LLM inference server setup using [llama.cpp](https://github.com/ggml-org/llama.cpp).
  - `build.sh`: Clones and builds llama.cpp with Metal acceleration, native optimizations, and LTO.
  - `serve.sh`: Starts the llama-server with GPU offloading, flash attention, and Jinja templating support.
- **`manifest/`**: [Manifest](https://github.com/mnfst/manifest) tool setup and starter/stopper.
  - `setup.sh`: Clones the manifest repository to `~/private/dev/manifest`.
  - `start.sh`: Starts the Manifest docker environment using `nerdctl compose`.
  - `stop.sh`: Stops the Manifest docker environment.
- **`colima/`**: Configurations for Colima profiles (Docker, Containerd, AI).
- **`direnv/`**: Configuration for `direnv` (`direnv.toml`).

## Setup Instructions

### First setup

Execute `macos/init.sh` once to setup your mac.

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

# Add bash completion directory
mkdir -p ~/.config/bash_completion.d

# Start automatic updates every 12 hours, immediatelly and on system boot if on AC power.
# Passes --sudo as well to enable upgrading casks. The updater may ask for a password.
brew autoupdate start 43200 --immediate --upgrade --cleanup --ac-only --sudo
```

#### docker-buildx

The `docker-buildx` plugin is installed to enable extended build capabilities with BuildKit.

You have to add the following to your `~/.docker/config.json`:

```json
  "cliPluginsExtraDirs": [
      "/opt/homebrew/lib/docker/cli-plugins"
  ]
```

### Dotfiles

Symlink the dotfiles to your home directory:

```bash
find "$(pwd)/dotfiles" -maxdepth 1 -name ".*" -exec ln -sf {} "$HOME" \;
ln -s $(pwd)/direnv ~/.config/
mkdir ~/.ssh
ln -s $(pwd)/ssh/config ~/.ssh/
ln -s $(pwd)/ssh/allowed_signers ~/.ssh/
ln -s $(pwd)/omlx/settings.json ~/.omlx/
```

### OpenCode (AI Agent harness)

Symlink the opencode directory to the global configs:

```bash
ln -s $(pwd)/opencode ~/.config/opencode
```

Ensure your API keys (e.g., for Google Gemini) are securely configured in your local environment, as they are excluded from this repository.

### macOS Shortcuts

The `macos/automation/shortcuts/` directory contains `.cherri` source code files that can be compiled and then imported into the macOS Shortcuts app. These are useful for context switching and automating your workflow.

Available Shortcuts:

- `dev-start` / `dev-stop`: Opens/hides the development environment (Zed, Terminal) and manages the local `ollama` service.
- `mail-start` / `mail-stop`: Opens/hides communication applications (Microsoft Teams and Outlook).
- `meeting-start` / `meeting-stop`: Prepares the system for a meeting (hides unrelated apps, focuses Microsoft Teams).
- `private-start` / `private-stop`: Prepares the system for private time (hides work apps, opens Steam).

These shortcuts are written in [Cherri](https://github.com/electrikmilk/cherri) (`*.cherri`). You need to compile them using the Cherri CLI to generate `.shortcut` files, which can than be imported.

On can hook the start scripts to focus change events if you add corresponding focus modes (`dev`, `mail`, `meeting`, `private`).

Compile and import all shortcuts (opens the Shortcuts app with multiple acknowledgement dialogs):

```bash
find macos/automation/shortcuts -name '*-*.cherri' -exec echo {} ';' -exec cherri {} --open ';'
```

#### How to retrieve Bundle ID of an app?

```bash
osascript -e 'id of app "APPNAME"'
```

### Git Configuration

This repository includes custom git configurations (`.gitconfig`):

- User name and email, separate for work and private projects
- Git GPG signing enabled, using SSH for signing
- Autocorrect for mistyped commands
- File system monitor for faster status checks
- Default branch set to `main`
- Merge tool configured for opendiff
- Automatic pushing of relevant annotated tags

### Ollama (local LLMs)

Brew starts the local Ollama service. You can pull required models, e.g. those configured in `opencode.jsonc` by calling `ollama run <model>`.

Or build the models from a Modelfile:

```bash
ollama create tiny -f ollama/models/Modelfile.tiny
```

### OMLX (LLM Inference)

OMLX is an inference server for running LLM models on metal hardware locally.

Symlink the configuration to your home directory:

```bash
ln -s $(pwd)/omlx/settings.json ~/.omlx/
```

The configuration includes server settings, model directories, memory management, SSD caching, and sampling parameters.

### MTPLX (Model Serving)

MTPLX provides optimized model serving for large language models (e.g., Qwen3.6-27B).

To start the MTPLX server:

```bash
mtplx/serve.sh
```

### llama.cpp (Local LLM Inference)

llama.cpp provides local LLM inference with GPU acceleration (Metal on macOS).

To build llama.cpp from source:

```bash
bash llama.cpp/build.sh
```

To start the inference server:

```bash
bash llama.cpp/serve.sh
```

### Manifest

Manifest provides local repo updater and starter/stopper for Docker compose.

To setup Manifest:

```bash
bash manifest/setup.sh
```

To start the Manifest environment:

```bash
bash manifest/start.sh
```

To stop the Manifest environment:

```bash
bash manifest/stop.sh
```

Ensure to create and edit `~/private/dev/manifest/docker/.env` before running.

### macOS Build Tools

The `macos/bin/` directory contains build scripts for various tools:

- **LlamaWatch**: macOS app for monitoring Ollama
  ```bash
  bash macos/bin/llamawatch/build.sh
  ```
- **Apple On-Device OpenAI**: Xcode project for on-device AI
  ```bash
  bash macos/bin/apple-on-device-openai/build.sh
  ```
- **Timelog**: CLI time tracking tool
  ```bash
  bash macos/bin/timelog/build.sh
  ```
- **Cherri**: CLI compiler for macOS Shortcuts
  ```bash
  bash macos/bin/cherri/build.sh
  ```

All tools are built from source and installed to `~/private/dev/`.

### Colima

Provides container environment for docker and nerdctl.

Configures the following virtual machines (profiles):

- `docker`: Machine for docker environment, accessible through `docker`, runs with apples vz virtualization framework for best performance, in theory, but file system failures in practice.
- `docker-qemu`: Machine for docker environment, accessible through `docker`, runs with qemu virtualization framework and sshfs for better stability, but worse performance.
- `containerd`: Bare containers, accessible through `nerdctl`
- `ai`: krunkit environment to run LLMs

No VM is started by default. Start a profile with `colima start <profile>`.

Perform the following for installation:

```bash
ln -s $(pwd)/colima ~/.colima

colima completion bash > ~/.config/bash_completion.d/colima
colima -p containerd nerdctl install
```

#### lazydocker

For monitoring the docker environment, one can use [lazydocker](https://github.com/jesseduffield/lazydocker), which is running via docker in docker. Execute the `lazydocker` alias.

If you're on an ARM device (which you probably are with Apple silicon), you need to build the image yourself. See the [full instructions here](https://github.com/jesseduffield/lazydocker#docker):

```bash
docker build -t lazyteam/lazydocker \
  --build-arg BASE_IMAGE_BUILDER=arm64v8/golang \
  --build-arg GOARCH=arm64 \
  https://github.com/jesseduffield/lazydocker.git
```

## Things others would have to adjust

- Full path containing my username `mkuckert`, e.g. in `mtplx/serve.sh`, `llama.cpp/serve.sh`, `omlx/settings.json`
- The `dotfiles/.gitconfig*` files
- The `ssh/*` config files
- The `opencode.jsonc` MCP gateway paths (`/Users/mkuckert/private/dev/agent-harness/bin/docker-mcp-gateway-run.sh`)

## Source

Most is my own work.

Some of the `dotfiles` are inspired from [Mathias Bynens](https://github.com/mathiasbynens/dotfiles) but heavily modified to match my preferences.
