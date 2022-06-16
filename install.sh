#!/bin/bash

SCRIPT="do-terraform.sh"
COMMAND="do-terraform"
INSTALL_DIR="/usr/local/bin"

if [[ ! -d $INSTALL_DIR ]]; then
  mkdir -p $INSTALL_DIR
fi

# Copy Script and make soft link
cp $SCRIPT $INSTALL_DIR
ln -s $INSTALL_DIR/$SCRIPT $INSTALL_DIR/$COMMAND

# Add Execute Permission
chmod +x $INSTALL_DIR/$SCRIPT
chmod +x $INSTALL_DIR/$COMMAND

# Add Path to profile
echo 'export PATH="$PATH":$INSTALL_DIR' >> ~/.profile
source ~/.profile
