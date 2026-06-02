#!/bin/bash
# Marveen - OS-detect wrapper
# Detects the operating system and launches the appropriate installer.

case "$(uname -s)" in
  Darwin)
    exec "$(dirname "$0")/install-macos.sh" "$@"
    ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      exec "$(dirname "$0")/install-wsl.sh" "$@"
    else
      exec "$(dirname "$0")/install-linux.sh" "$@"
    fi
    ;;
  *)
    echo "Nem tamogatott operacios rendszer: $(uname -s)"
    echo "Tamogatott: macOS (Darwin), Linux (Ubuntu/Debian)"
    exit 1
    ;;
esac
