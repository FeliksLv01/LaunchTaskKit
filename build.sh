#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec ruby Scripts/build_macro.rb "$@"
