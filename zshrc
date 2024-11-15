# Explicitly configured $PATH variable
PATH=/usr/local/git/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/opt/local/bin:/opt/local/sbin:/usr/X11/bin:/Users/howdy/.nvm/versions/node/v18.14.2

# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
ZSH_THEME="powerlevel10k/powerlevel10k"
# change zsh-autosuggestions color
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=60'

# Uncomment following line if you want red dots to be displayed while waiting for completion
COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  zsh-autosuggestions
  yarn
  web-search
  jsontools
  macports
  node
  macos
  sudo
  thor
  docker
  zsh-completions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# Enable brew recognition with Apple M1
eval $(/opt/homebrew/bin/brew shellenv)

# Put any proprietary or private functions/values in ~/.private, and this will source them
if [ -f $HOME/.private ]; then
  source $HOME/.private
fi

if [ -f $HOME/.profile ]; then
  source $HOME/.profile  # Read Mac .profile, if present.
fi

# Shell Functions
# qfind - used to quickly find files that contain a string in a directory
qfind () {
  find . -exec grep -l -s $1 {} \;
  return 0
}

# Custom exports
## Set EDITOR to /usr/bin/vim if Vim is installed
if [ -f /usr/bin/vim ]; then
  export EDITOR=/usr/bin/vim
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# Reload the plugin to highlight the commands each time Iterm2 starts
source $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Colorise the top Tabs of Iterm2 with the same color as background
# Just change the 18/26/33 wich are the rgb values
echo -e "\033]6;1;bg;red;brightness;18\a"
echo -e "\033]6;1;bg;green;brightness;26\a"
echo -e "\033]6;1;bg;blue;brightness;33\a"

# Configure terminal to work with vim key bindings
set -o vi

export NVM_DIR=~/.nvm
# Set nvim default git editor
export GIT_EDITOR=nvim
source $(brew --prefix nvm)/nvm.sh
# This loads nvm bash_completion
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  

# The next line updates PATH for the Google Cloud SDK.
# if [ -f '/Users/dobregon/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/dobregon/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
# if [ -f '/Users/dobregon/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/dobregon/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

source ~/.oH-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Autocompletion saml2aws
eval "$(saml2aws --completion-script-zsh)"

# Shell Aliases
alias vi='vim'
## Miscellaneous Aliases
alias htop='sudo htop'
# LS lists information about files.
# show slashes for directories.
alias ls='ls -laF'
# long list format including hidden files and include unit size
alias ll='ls -la'
# J1 Aliases
alias saml2awslogin='saml2aws login --idp-account="default" --verbose --force'
alias managed-integration-upgrade='~/GitProjects/integration-engineering-toolbox/managed-integration-upgrade/managed-integration-upgrade.sh'
alias aws-dev='aws --profile jupiterone-dev'
alias managed-integration-upgrade='~/GitProjects/integration-engineering-toolbox/managed-integration-upgrade/managed-integration-upgrade.sh'
alias stop-all-containers='docker stop $(docker ps -a -q)'
alias remove-all-containers='docker rm $(docker ps -a -q)'
alias start-local-db='~/db-conn.sh'
alias clean-swap-files='find . -type f -name "*.sw[klmnop]" -delete'

autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/howdy/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/howdy/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/howdy/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/howdy/google-cloud-sdk/completion.zsh.inc'; fi

# Set java version to corretto 8
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export PATH="$JAVA_HOME/bin:$PATH:~/.local/bin"

