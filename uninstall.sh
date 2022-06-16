#!/bin/bash

SCRIPT="do-terraform.sh"
COMMAND="do-terraform"
INSTALL_DIR="/usr/local/bin"

rm $INSTALL_DIR/$COMMAND
rm $INSTALL_DIR/$SCRIPT
sed -i '/export PATH="$PATH":$INSTALL_DIR/d' ~/.profile
