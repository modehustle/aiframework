# Scaffold: laying down the foundation, .gitignore, the repository, the copy notice.
M_scaf_gitignore_closed='.gitignore — secrets are already covered, left alone'
M_scaf_gitignore_added='.gitignore — added:{patterns}'
M_scaf_env_tracked='.env is already in the git history — .gitignore does not take it out of there'
M_scaf_env_tracked_hint='change the secrets and remove the file from the index; cleaning the history is a separate job'

M_scaf_no_templates_broken='foundation templates not found — the installation is damaged'
M_scaf_no_templates='foundation templates not found: {path}'
M_scaf_exists='{path} — already exists, left alone'
M_scaf_ctx_updated='{file} — the fraim block updated, the rest untouched'
M_scaf_err_write='could not write {file}'
M_scaf_created='created: {created}'
M_scaf_created_skipped='created: {created}, left as it was: {skipped}'

M_scaf_git_missing='git not found — there will be no save points'
M_scaf_git_missing_hint='install git: without it the verbs cannot save a single change'
M_scaf_git_exists='git — the repository already exists, left alone'
M_scaf_git_nested='git — the project is inside the repository {top}, not creating its own'
M_scaf_git_init_failed='could not create the repository'
M_scaf_git_init_done='git — repository created'
M_scaf_git_identity='commit signatures were not configured — set local ones for this project'
M_scaf_git_identity_hint='to change: git config user.name "Name" && git config user.email "email"'

M_scaf_copy_notice_where='The project'\''s history lives in this same folder — there is no copy off this machine.'
M_scaf_copy_notice_how='Need a copy of the code and history (data and secrets do not go into it) — fraim publish.'

M_scaf_section_added='CONVENTIONS.md — added the «{section}» section'
