# The watchman's verdict: findings and the actions they point at.
M_wm_inv_no_findings_one='investigation «{slug}» has no findings.md — no outcome, no cleanup report ({n} day)'
M_wm_inv_no_findings_other='investigation «{slug}» has no findings.md — no outcome, no cleanup report ({n} days)'
M_wm_act_inv_no_findings='/investigate or fraim clean'
M_wm_inv_done='investigation «{slug}» is finished and not archived'
M_wm_inv_stale_one='investigation «{slug}» open for {n} day without an outcome'
M_wm_inv_stale_other='investigation «{slug}» open for {n} days without an outcome'
M_wm_inv_active='investigation «{slug}» in progress'

M_wm_git_missing='git is not installed — there are no save points'
M_wm_act_install_git='install git'
M_wm_git_no_repo='there is no repository — there are no save points'

M_wm_remote_none='there is no remote copy — the project lives only on this machine'
M_wm_remote_never='a copy address is set, but nothing has ever gone there'
M_wm_remote_unpushed_one='{n} save point has not gone to the remote copy'
M_wm_remote_unpushed_other='{n} save points have not gone to the remote copy'

M_wm_dirty_one='{n} file of the foundation and ai/ changed since the last save point'
M_wm_dirty_other='{n} files of the foundation and ai/ changed since the last save point'

M_wm_worktrees_one='{n} parallel checkout: {names}'
M_wm_worktrees_other='{n} parallel checkouts: {names}'

M_wm_queue_one='{n} open task on the board'
M_wm_queue_other='{n} open tasks on the board'

M_wm_shape_no_block='(no block)'
M_wm_shape_old_tasks='old-format'
M_wm_shape='the foundation is behind the standard:{missing}'

M_wm_no_arch='there is no ARCHITECTURE.md — the foundation is not laid'
M_wm_stubs_one='the skeleton is laid out but not filled: {n} file —{files}'
M_wm_stubs_other='the skeleton is laid out but not filled: {n} files —{files}'
M_wm_act_bootstrap='/bootstrap or /onboard'
M_wm_arch_lag_one='{n} code commit since ARCHITECTURE.md was last updated'
M_wm_arch_lag_other='{n} code commits since ARCHITECTURE.md was last updated'
M_wm_lessons_lag_one='{n} code commit since CONVENTIONS.md last gained an entry — no pitfalls were written down'
M_wm_lessons_lag_other='{n} code commits since CONVENTIONS.md last gained an entry — no pitfalls were written down'

M_wm_update='a new fraim version on the host ({rev})'

M_wm_language_one='{n} foundation fragment not in English: {files}'
M_wm_language_other='{n} foundation fragments not in English: {files}'
M_wm_act_language='/prune — translate into English'

M_wm_all_clean='{name} — all clean'
