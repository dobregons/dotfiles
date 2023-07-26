#!/bin/bash

# Check if nvm is already installed, if not, install it
if ! command -v nvm &> /dev/null; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
  # This command will install nvm version 0.39.1. You can replace it with the latest version if available.
  # Make sure to check the nvm repository for the latest version: https://github.com/nvm-sh/nvm
fi

# Load nvm to the current shell
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  

# Install the Node.js version specified in .nvmrc
nvm install

# Optionally, set this version as the default for new shells
nvm alias default $(cat .nvmrc)
