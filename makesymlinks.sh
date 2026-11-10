#!/bin/bash
set -euo pipefail

dir=~/dotfiles
olddir=~/dotfiles_old

mkdir -p "$olddir" ~/.config/cmux ~/.claude/skills ~/.agents

link() {
  local src="$dir/$1" dest="$2"
  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -e "$dest" ]; then
    mv "$dest" "$olddir/"
  fi
  ln -s "$src" "$dest"
  echo "linked $dest"
}

copy_if_missing() {
  if [ -e "$2" ]; then
    echo "kept $2"
  else
    cp -R "$dir/$1" "$2"
    echo "copied $2"
  fi
}

link zshrc ~/.zshrc
link .p10k.zsh ~/.p10k.zsh
link gitconfig ~/.gitconfig
link gitignore_global ~/.gitignore_global
link vimrc ~/.vimrc
link vim ~/.vim
link .tmux.conf ~/.tmux.conf
link .config/kitty ~/.config/kitty
link .config/zellij ~/.config/zellij
link claude/CLAUDE.md ~/.claude/CLAUDE.md
link claude/commands ~/.claude/commands
link claude/agents ~/.claude/agents
link claude/statusline-command.sh ~/.claude/statusline-command.sh
link .agents/skills ~/.agents/skills

for skill in "$dir"/.agents/skills/*/; do
  name=$(basename "$skill")
  ln -sfn "../../.agents/skills/$name" ~/.claude/skills/"$name"
done

# Apps rewrite these files atomically, which would replace a symlink with a plain file
copy_if_missing claude/settings.json ~/.claude/settings.json
copy_if_missing .agents/.skill-lock.json ~/.agents/.skill-lock.json
copy_if_missing .config/cmux/cmux.json ~/.config/cmux/cmux.json
