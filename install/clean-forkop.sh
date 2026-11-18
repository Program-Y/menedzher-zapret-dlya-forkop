#!/bin/sh
# Только очистка: без установки Forkop/sing-box.
# Запуск: sh install/clean-forkop.sh
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec sh "$SCRIPT_DIR/install-forkop.sh" --clean-only
