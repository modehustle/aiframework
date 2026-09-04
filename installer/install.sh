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
    say "обновляю $SRC ($BRANCH)"
    # Explicit refspec, then `checkout -B` from the remote-tracking ref. The clone below
    # is made with --depth 1 --branch, which implies --single-branch: its fetch refspec
    # mentions main and nothing else. So the documented way to try an unmerged branch —
    # FRAIM_BRANCH=… sh install.sh — used to fetch the commits into FETCH_HEAD and then
    # fail on `checkout <branch>` with "pathspec did not match", on every machine that
    # already had fraim installed.
    git -C "$SRC" fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" ||
        die "не удалось получить ветку $BRANCH из $REPO"
    # --force because $SRC is our copy of the source tree, never the user's work: a stray
    # mode bit or a poked-at file there must not turn an update into a git lecture about
    # stashing, addressed to someone the product promises never has to know git.
    git -C "$SRC" checkout --quiet --force -B "$BRANCH" "refs/remotes/origin/$BRANCH" ||
        die "не удалось переключиться на $BRANCH"
    git -C "$SRC" reset --hard --quiet "refs/remotes/origin/$BRANCH"
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
