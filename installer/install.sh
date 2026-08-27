#!/bin/sh
# install.sh — put fraim on this machine, then hand over to `fraim init`.
#
#   curl -fsSL https://raw.githubusercontent.com/modehustle/aiframework/main/installer/install.sh | sh
#
# Copies the source tree to ~/.fraim/src and links the binary. No build step,
# no runtime, no package manager: everything here is POSIX shell and markdown.

set -eu

REPO=${FRAIM_REPO:-https://github.com/modehustle/aiframework}
BRANCH=${FRAIM_BRANCH:-main}
FRAIM_HOME=${FRAIM_HOME:-$HOME/.fraim}
BIN_DIR=${FRAIM_BIN_DIR:-$HOME/.local/bin}
SRC="$FRAIM_HOME/src"

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "нужен git"

mkdir -p "$FRAIM_HOME" "$BIN_DIR"

if [ -d "$SRC/.git" ]; then
    say "обновляю $SRC"
    git -C "$SRC" fetch --quiet origin "$BRANCH"
    git -C "$SRC" checkout --quiet "$BRANCH"
    git -C "$SRC" reset --hard --quiet "origin/$BRANCH"
else
    say "клонирую $REPO"
    rm -rf "$SRC"
    git clone --quiet --depth 1 --branch "$BRANCH" "$REPO" "$SRC"
fi

ln -sf "$SRC/installer/bin/fraim" "$BIN_DIR/fraim"
chmod +x "$SRC/installer/bin/fraim"

say "установлено: $BIN_DIR/fraim -> $SRC/installer/bin/fraim"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        say ""
        say "ВАЖНО: $BIN_DIR не в PATH. Добавь в свой профиль:"
        say "    export PATH=\"\$PATH:$BIN_DIR\""
        ;;
esac

say ""
say "Дальше: fraim init"
