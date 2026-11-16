#!/bin/bash
#
# Prepara um worktree do zsh-map para o Orca: reserva slot e sobe o compose de teste
# (docker/) com projeto isolado ${COMPOSE_PREFIX}<N>.
#
# Uso: scripts/orca-setup.sh              prepara (build + up)
#      scripts/orca-setup.sh --teardown   derruba compose e libera slot
#      scripts/orca-setup.sh --status

set -euo pipefail

MAX_SLOT=6
COMPOSE_PREFIX="zshmap-wt"
COMPOSE_FILE="docker/compose.yml"

fail() { echo "Erro: $*" >&2; exit 1; }

WORKTREE="$(git rev-parse --show-toplevel)"
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
PRIMARY="$(dirname "$GIT_COMMON_DIR")"
REGISTRY="$GIT_COMMON_DIR/orca-slots.tsv"
SLOT=""

lock_registry() {
    exec 9>"$GIT_COMMON_DIR/orca-slots.lock"
    flock -w 60 9 || fail "outro setup está segurando o registro de slots há mais de 60 s"
}
unlock_registry() { exec 9>&-; }

compose_of() { echo "${COMPOSE_PREFIX}$1"; }

read_live_entries() {
    touch "$REGISTRY"
    while IFS=$'\t' read -r entry_slot entry_port entry_path; do
        [ -z "$entry_slot" ] && continue
        if [ -d "$entry_path" ]; then
            printf '%s\t%s\t%s\n' "$entry_slot" "$entry_port" "$entry_path"
        fi
    done <"$REGISTRY"
}

reserve_slot() {
    local live used candidate
    live="$(read_live_entries)"
    SLOT="$(printf '%s\n' "$live" | awk -F'\t' -v path="$WORKTREE" '$3 == path { print $1 }')"
    if [ -z "$SLOT" ]; then
        used=" $(printf '%s\n' "$live" | cut -f1 | tr '\n' ' ')"
        for candidate in $(seq 1 "$MAX_SLOT"); do
            if [[ "$used" != *" $candidate "* ]]; then SLOT="$candidate"; break; fi
        done
    fi
    [ -n "$SLOT" ] || fail "todos os $MAX_SLOT slots estão ocupados"
    live="$(printf '%s\n' "$live" | awk -F'\t' -v path="$WORKTREE" '$3 != path')"
    live="$(printf '%s\n%s\t0\t%s' "$live" "$SLOT" "$WORKTREE")"
    printf '%s\n' "$live" | sed '/^$/d' >"$REGISTRY"
}

release_slot() {
    local live
    live="$(read_live_entries)"
    SLOT="$(printf '%s\n' "$live" | awk -F'\t' -v path="$WORKTREE" '$3 == path { print $1 }')"
    printf '%s\n' "$live" | awk -F'\t' -v path="$WORKTREE" '$3 != path' | sed '/^$/d' >"$REGISTRY"
}

start_compose() {
    local project
    project="$(compose_of "$SLOT")"
    docker info >/dev/null 2>&1 || fail "o Docker não está rodando"
    [ -f "$WORKTREE/$COMPOSE_FILE" ] || fail "falta $COMPOSE_FILE"
    mkdir -p "$WORKTREE/.orca"
    echo "ORCA_SLOT=$SLOT" >"$WORKTREE/.orca/env"
    echo "COMPOSE_PROJECT_NAME=$project" >>"$WORKTREE/.orca/env"
    (cd "$WORKTREE/docker" && COMPOSE_PROJECT_NAME="$project" docker compose -f compose.yml build --quiet)
    (cd "$WORKTREE/docker" && COMPOSE_PROJECT_NAME="$project" docker compose -f compose.yml up -d)
    echo "  compose $project no ar"
}

stop_compose() {
    local project
    [ -n "$SLOT" ] || return
    project="$(compose_of "$SLOT")"
    if [ -f "$WORKTREE/$COMPOSE_FILE" ]; then
        (cd "$WORKTREE/docker" && COMPOSE_PROJECT_NAME="$project" docker compose -f compose.yml down --remove-orphans >/dev/null 2>&1) || true
    fi
    rm -rf "$WORKTREE/.orca"
}

setup() {
    lock_registry; reserve_slot; unlock_registry
    echo "zsh-map no Orca: slot $SLOT"
    echo "  worktree: $WORKTREE"
    start_compose
    echo
    echo "Pronto. Shell de teste: docker compose -p $(compose_of "$SLOT") -f docker/compose.yml run --rm app zsh"
}

teardown() {
    lock_registry; release_slot; unlock_registry
    stop_compose
    if [ -z "$SLOT" ]; then echo "Este worktree não tem slot: nada a liberar."; return; fi
    echo "Slot $SLOT liberado e compose removido."
}

status() {
    lock_registry
    echo "Slot 0: zsh-map · $PRIMARY"
    while IFS=$'\t' read -r entry_slot entry_port entry_path; do
        [ -z "$entry_slot" ] && continue
        echo "Slot $entry_slot: $(compose_of "$entry_slot") · $entry_path"
    done < <(read_live_entries)
    unlock_registry
}

case "${1:-}" in
    --status) status ;;
    --teardown)
        [ -n "${2:-}" ] && WORKTREE="${2%/}"
        [ "$WORKTREE" = "$PRIMARY" ] && fail "o checkout principal não tem slot para liberar"
        teardown
        ;;
    "")
        if [ "$WORKTREE" = "$PRIMARY" ]; then
            echo "zsh-map no Orca: slot 0 (checkout principal)"
            echo "Nada a fazer no principal; worktrees usam compose ${COMPOSE_PREFIX}<N>."
        else
            setup
        fi
        ;;
    *) fail "opção desconhecida: $1" ;;
esac
