#!/bin/bash
set -e

export NGINX_VERSION=$1
export NGINX_SHA256=$2
export MODE=$3
export CUSTOM_LIST=$4

export BASE_DIR=$(dirname "$0")
export MODULES_DEF_FILE="/modules.conf"
export PROFILES_DEF_FILE="/profiles.conf"
export LIB_DIR="$BASE_DIR/scripts"
echo $LIB_DIR
echo ">>> [1/4] Initializing Environment..."
source "$LIB_DIR/00_init.sh"

echo ">>> [2/4] Preparing Modules ($MODE)..."
source "$LIB_DIR/01_modules.sh"

echo ">>> [3/4] Compiling Nginx..."
source "$LIB_DIR/02_engine.sh"

echo ">>> [4/4] Finalizing & Cleanup..."
source "$LIB_DIR/03_finish.sh"

echo ">>> Build Complete Successfully."