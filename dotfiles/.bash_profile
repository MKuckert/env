#!/usr/bin/env bash
export PATH="${HOME}/bin:$PATH"

# Load other shell dotfiles
for file in ~/.{path,bash_prompt,exports,aliases}; do
	[ -r "$file" ] && [ -f "$file" ] && source "$file";
done;
unset file;

# Append to the Bash history file, rather than overwriting it
shopt -s histappend;

# Autocorrect typos in path names when using `cd`
shopt -s cdspell;

# Enable `**/qux` to enter `./foo/bar/baz/qux`
shopt -s autocd

# Enable recursive globbing, e.g. `echo **/*.txt`
shopt -s globstar

# Add tab completion for many Bash commands
if [ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]; then
	source "$(brew --prefix)/etc/profile.d/bash_completion.sh";
elif [ -f /etc/bash_completion ]; then
	source /etc/bash_completion;
fi;

# Add fuzzy finder
eval "$(fzf --bash)"
