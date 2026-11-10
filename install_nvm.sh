#!/bin/bash

export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
. "$(brew --prefix nvm)/nvm.sh"

nvm install
nvm alias default "$(cat .nvmrc)"
