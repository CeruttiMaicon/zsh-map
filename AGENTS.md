## Worktrees do Orca

Num worktree criado pelo Orca, `bash scripts/orca-setup.sh` reserva um slot e sobe o
compose em `docker/` com projeto `zshmap-wt<N>`.

- Status: `bash scripts/orca-setup.sh --status`
- Teardown: `bash scripts/orca-setup.sh --teardown` (hook `archive` do Orca)
