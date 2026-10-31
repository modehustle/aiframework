# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim — the operational layer for agent-driven projects

You type these
  fraim                     the fraim screen (in a terminal) — same as fraim menu
  fraim menu                project, board, backlog, decisions, settings and language on one screen
  fraim status [PATH]       what is going on in the project (--json for machines)
  fraim fleet [PATH]        where the work lives: the project'\''s checkouts
  fraim undo [HASH]         list the save points / put things back as they were
  fraim scaffold [PATH]     bring a project under the system
  fraim upgrade [PATH]      bring every registered project up to this version'\''s standard
                            (PATH — this project only)
  fraim clean [--yes]       tidy up everything that is fixed without judgement
  fraim publish [--check]   a copy of the project off this machine: create, push, verify
                            (--brief — a task for the agent to clean out what was found)
  fraim dispatch PLAN       fleet: check the plan and open a build
  fraim dispatch collect BUILD  merge the round'\''s results into the build branch
  fraim dispatch accept BUILD   the conductor'\''s acceptance: verify, check, cleanup, trunk
                            prepare BUILD — checkouts for a harness without isolation
                            verify BUILD SUBTASK [BRANCH] — one result against its paths
                            check PLAN · list
  fraim mode                remove leftovers of the old fleet mode from the project
  fraim init                install the skills / pick up a new harness
  fraim update [--check]    fetch the new version and lay it out (--check — only find out;
                            --quiet — for autostart: silent, never in the way of a start)
  fraim doctor              what is installed where, what has drifted
  fraim config              what is in effect and where from (set / unset KEY)
  fraim projects            the project registry (add PATH / rm PATH)

Agents and procedures call these — you need not remember them'
M_cli_usage_tail='
Service
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            removed together with plans: a task is a card now
  fraim roles               removed with the role table: a worker runs on the agent'\''s own model
  fraim show NAME           print a procedure'\''s text
  fraim build               rebuild the repository'\''s artifacts
  fraim version             the version
  fraim help                this screen

The watchman is deterministic: files, git log and mtime. No model, no network, and it
writes nothing. It notices — the human decides.'

# Shared words.
M_cli_err_unknown_command='unknown command: {cmd}'
M_cli_err_unknown_flag='unknown flag: {flag}'
M_cli_err_subcommand='unknown subcommand: {sub}'
M_cli_err_no_dir='no such directory: {path}'
M_cli_err_no_procedures='procedures/ directory not found'
M_cli_err_need_path='give a path'
M_cli_err_not_project='no ai/ here — this is not a project under the system (fraim scaffold)'
M_cli_registered='project registered: {path}'
M_cli_context_block='context block → {path}'
M_cli_cancelled='cancelled'

# init
M_cli_init_err_broken='procedures/ directory not found — the installation is damaged'
M_cli_init_source='fraim {ver} · source: {root}'
M_cli_init_skills_built='skills built: {n} (procedures + master skill)'
M_cli_init_harness_dir_failed='{label}: installing into {dir} failed'
M_cli_init_swept='moved from its old place: {path}'
M_cli_init_context_failed='{label}: could not update {path}'
M_cli_init_no_harness='no harness found'
M_cli_init_no_harness_copy='the skills are built in {path} — copy them into your agent'\''s directory by hand,'
M_cli_init_no_harness_rerun='or install a harness and run '\''fraim init'\'' again (the command is idempotent).'
M_cli_init_registry_count='projects in the registry: {n} — bring them up to this version: fraim upgrade'
M_cli_init_done='Done. Check: {cmd}'
M_cli_perm_added='permission Bash(fraim:*) added to ~/.claude/settings.json'
M_cli_perm_hint='Claude Code: add "Bash(fraim:*)" to permissions.allow in ~/.claude/settings.json'

# update
M_cli_upd_not_clone='the source is not a git clone — nothing to check'
M_cli_upd_network_hint='network or repository access: check git ls-remote'
M_cli_upd_latest='the latest version is installed ({ver})'
M_cli_upd_updated='fraim updated: {from} → {to}'
M_cli_upd_err_flag='fraim update: unknown option: {flag}'
M_cli_upd_title='Updating fraim'
M_cli_upd_was='was: {ver}'

# status
M_cli_status_unmanaged='{path} is not under the system: neither ai/ nor ARCHITECTURE.md'
M_cli_status_unmanaged_hint='bring an existing project in — /onboard; a new one — /design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_one='{n} task on the board'
M_cli_fleet_on_board_other='{n} tasks on the board'
M_cli_fleet_clean='clean'
M_cli_fleet_err_not_repo='{path} is not a repository — there are no checkouts and cannot be'

# projects
M_cli_proj_no_dir='(no directory)'
M_cli_proj_empty='the registry is empty — '\''fraim projects add PATH'\'' or run '\''fraim init'\'' in a project'
M_cli_proj_added='added: {path}'
M_cli_proj_removed='removed: {path}'

# doctor
M_cli_doc_source_git='source: {root} ({branch} {sha}, {date})'
M_cli_doc_source='source: {root}'
M_cli_doc_state='state:  {path}'
M_cli_doc_latest='latest known version'
M_cli_doc_procedures='Procedures'
M_cli_doc_harnesses='Harnesses'
M_cli_doc_skills_ok='{n} skills, version {ver}'
M_cli_doc_skills_mismatch='{n} skills, versions: {vers}(installed {ver} — fraim init needed)'
M_cli_doc_no_skills='found, skills not installed — run fraim init'
M_cli_doc_not_found='not found'
M_cli_doc_registry='Project registry'
M_cli_doc_registry_empty='empty'
M_cli_doc_registry_count='projects: {n}'
M_cli_doc_registry_gone='directory is gone: {path}  ('\''fraim projects rm'\'' to remove it)'

# show, build
M_cli_show_err_need_name='give a procedure name: {list}'
M_cli_show_err_unknown='no such procedure: {name}'
M_cli_build_plugin='Claude Code plugin: {n} skills'
M_cli_build_manifest='manifest: procedures/manifest.json'

# scaffold
M_cli_scaf_title='Foundation skeleton in {path}'
M_cli_scaf_err='could not lay down the skeleton'
M_cli_scaf_registered='project registered in the registry'
M_cli_scaf_next='Next: {bootstrap} for a new project, {onboard} for existing code.'
M_cli_scaf_stub_note='The files carry the fraim:stub marker — the watchman counts them as unfilled while it is there.'

# upgrade
M_cli_upg_err_empty='the project registry is empty — '\''fraim upgrade PATH'\'' for one project or '\''fraim init'\'' in a project'
M_cli_upg_skip_no_dir='no directory — skipped; remove it from the registry: fraim projects rm {path}'
M_cli_upg_skip_unmanaged='not under the system — skipped'
M_cli_upg_summary='Projects: upgraded {ok}, skipped {skip}, failed {fail}'
M_cli_upg_err_unmanaged='nothing to upgrade here: this is not a project under the system. Start one — fraim scaffold'
M_cli_upg_title='Bringing the foundation up to the fraim {ver} standard in {path}'
M_cli_upg_err_scaffold='could not upgrade the foundation'
M_cli_upg_err_sections='could not add the sections'
M_cli_upg_err_tasks='could not convert the old-format tasks'
M_cli_upg_conf_refreshed='ai/fraim.conf — the settings list refreshed, removed keys dropped'
M_cli_upg_done='done — check: fraim status'

# version
M_cli_ver_source='source: {root}'
M_cli_ver_git='branch {branch} · commit {sha} · {date}'
M_cli_ver_not_clone='source: {root} (not a git clone)'

# publish
M_cli_pub_err_provider_arg='--provider needs a name'
M_cli_pub_err_url_arg='--url needs a link'
M_cli_pub_err_name_arg='--name needs a name'
M_cli_pub_err_flag='unknown flag: {flag} (see fraim help)'
M_cli_pub_err_extra='extra argument: {arg} — the name is given with --name'
M_cli_pub_err_provider='unknown provider: {prov} (github, gitlab, url)'
M_cli_pub_err_no_git='git is not installed — nothing to push with'
M_cli_pub_err_no_repo='no repository here — fraim scaffold creates one'
M_cli_pub_nothing_to_clean='nothing to clean out: the scan found nothing'
M_cli_pub_no_commits='not a single save point yet — nothing to push'
M_cli_pub_save_and_retry='save the work and try again: fraim clean, or fraim commit KIND TEXT PATH...'
M_cli_pub_copy='Copy: {url}'
M_cli_pub_never_pushed='nothing has ever been pushed there — the setup was started and not finished'
M_cli_pub_unpushed='save points not pushed: {n}'
M_cli_pub_all_pushed='by this machine'\''s records — everything has been pushed'
M_cli_pub_host_needs_net='what is actually on the host is checked by fraim publish: that needs the network'
M_cli_pub_no_copy='There is no copy off this machine.'
M_cli_pub_risk_private='to a private copy this goes with the risk accepted (fraim publish --private),'
M_cli_pub_risk_public='to a public one — no; to clean it out instead — fraim publish --brief'
M_cli_pub_asking_host='asking the host what is there…'
M_cli_pub_synced='the copy is in place and matches this machine: {url}'
M_cli_pub_err_choice='did not understand the choice'
M_cli_pub_err_no_target='where to publish was not said: --provider github|gitlab | --url LINK'
M_cli_pub_err_no_url='without a link there is nowhere to push'
M_cli_pub_err_url_needed='--provider url needs a link: --url LINK'
M_cli_pub_repo_name='repository name «{name}»: hosts accept only Latin letters, digits, dot and hyphen'
M_cli_pub_vis_src_yours='by your word'
M_cli_pub_force_warn='--force: the findings above will go to the host along with the history, and that cannot be undone'
M_cli_pub_ask_with_findings='Publish WITH the findings to the private copy? [y/N]'
M_cli_pub_ask='Publish? [y/N]'
M_cli_pub_plan_only='that was only the plan. To run it: fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='nothing to clean up here: this is not a project under the system'
M_cli_clean_ask='Start? [y/N]'
M_cli_clean_plan_only='that was only the plan. To run it: fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} is gone: a task is a card without a plan now — fraim tasks, task-new, task-seal (fraim help)'
M_cli_decide_usage='usage: fraim decide "TITLE" [--supersedes "WHAT IT REPLACES"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes needs a text'
M_cli_inv_err_slug='an investigation slug is needed'
M_cli_commit_usage='usage: fraim commit KIND TEXT PATH... (paths are required — there is no «everything»)'
M_cli_commit_err_kind='the kind must be one lowercase word: task, deploy, onboard, archive…'
M_cli_commit_err_no_git='no git here — there is nothing to put a save point into'
M_cli_commit_failed='the commit failed'

# dispatch
M_cli_disp_usage='usage: fraim dispatch PLAN (or check / prepare / collect / verify / accept / list)'
M_cli_disp_usage_check='usage: fraim dispatch check PLAN'
M_cli_disp_usage_verify='usage: fraim dispatch verify BUILD SUBTASK [BRANCH]'
M_cli_disp_usage_collect='usage: fraim dispatch collect BUILD [SUBTASK=BRANCH …]'
M_cli_disp_usage_accept='usage: fraim dispatch accept BUILD'
M_cli_disp_err_plan_bad='the plan does not fit parallel dispatch'
M_cli_disp_check_ok='the plan passes dispatch-check'
M_cli_disp_err_no_build_plan='no plan for build {build}'
M_cli_disp_err_no_subtask='build {build} has no subtask {sub}'
M_cli_disp_hint_collect='collect the round:  fraim dispatch collect {build} [SUBTASK=BRANCH …]'
M_cli_disp_collected='the round is collected into branch {branch}'
M_cli_disp_accept_hint='fraim dispatch accept {build}  (verification, master check, cleanup, report)'
M_cli_disp_err_collect_partial='the round is not fully collected — deal with the refused ones and try again'
M_cli_disp_err_accept='the acceptance failed'
M_cli_disp_accepted='build {build} accepted, checked and in the trunk'
M_cli_disp_not_accepted='build {build} checked, not taken into the trunk — sort it out and try again'
M_cli_disp_err_no_plan='no plan: {path}'
M_cli_disp_err_journal='could not open the build journal'
M_cli_disp_build_title='Build {build} — who does what:'
M_cli_disp_plan_hint_verify='check one result:  fraim dispatch verify {build} SUBTASK [BRANCH]'

# roles

# mode
M_cli_mode_gone='there are no modes any more: the agent works itself, in the conversation'
M_cli_mode_conductor_note='the conductor and the fleet are the /conductor procedure, started when the human asks'
M_cli_mode_err_conf='could not remove the mode line from ai/fraim.conf'
M_cli_mode_conf_done='the mode line removed from ai/fraim.conf'
M_cli_mode_err_agents='could not update AGENTS.md'
M_cli_mode_agents_done='the conductor block removed from AGENTS.md'
M_cli_mode_hook_done='the SessionStart hook removed from .claude/settings.json'
M_cli_mode_hook_no_python='no python3 — remove the «{mark}» hook from .claude/settings.json by hand'
M_cli_mode_hook_unreadable='.claude/settings.json could not be read — the «{mark}» hook is still there'
M_cli_mode_nothing='no leftovers of the old mode here'
M_cli_disp_usage_prepare='usage: fraim dispatch prepare BUILD'
M_cli_disp_retired='fraim dispatch {verb} is gone: workers are raised by your harness'\''s own subagents (/conductor, step 4); checkouts for a harness without isolation — fraim dispatch prepare BUILD'
M_cli_retired_roles='fraim roles is gone: workers run on the agent'\''s own model, unless the human names another one in words'
M_cli_disp_preparing='Checkouts for build {build}:'
M_cli_disp_err_prepare='not every checkout was created — see above'
M_cli_disp_hint_spawn_prepared='one subagent per checkout: it works there and reads its brief'
M_cli_disp_err_no_result='no result for subtask {sub}: name its branch, or prepare a checkout'
M_cli_disp_err_write_brief='could not write the brief of subtask {id}'
M_cli_disp_brief_written='brief {id} → {path}'
M_cli_disp_briefs_done='briefs written, journal opened: ai/builds/{build}/journal.md'
M_cli_disp_hint_spawn='raise one subagent per brief, each in its own worktree (your harness'\''s isolation)'
M_cli_disp_hint_prepare='no isolation in your harness:  fraim dispatch prepare {build}'
