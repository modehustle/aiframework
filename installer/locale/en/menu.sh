# The full-screen interface: sections, hints, dialogs, actions.
M_ui_sec_project='Project'
M_ui_sec_board='Board'
M_ui_sec_backlog='Backlog'
M_ui_sec_decisions='Decisions'
M_ui_sec_projects='Projects'
M_ui_sec_settings='Settings'
M_ui_sec_maint='Maintenance'

M_ui_unmanaged='this directory is not under the system — /onboard in the agent or fraim scaffold'
M_ui_watchman='Watchman'
M_ui_attention_one='{n} needs attention'
M_ui_attention_other='{n} need attention'
M_ui_all_clean='all clear'
M_ui_open_cards_one='{n} open card'
M_ui_open_cards_other='{n} open cards'
M_ui_board_empty='empty'
M_ui_questions_one='{n} question'
M_ui_questions_other='{n} questions'
M_ui_recent_decisions='Recent decisions'
M_ui_board_hint='To set work aside or open a project, tell the agent in words.'
M_ui_backlog_empty='the backlog is empty'
M_ui_backlog_hint='Enter — read the question. To turn it into a task or drop it, tell the agent.'
M_ui_projects_empty='the registry is empty — fraim init inside a project adds it'
M_ui_project_gone='directory is gone'
M_ui_act_register='Add this project to the registry'
M_ui_registered='project added to the registry'
M_ui_tier_cheap='Cheap models'
M_ui_tier_capable='Capable models'
M_ui_tier_strong='Strong models'
M_ui_expert_hint='Launching agents in the fleet: fraim config set --machine launchcmd_<agent> "…"'

M_ui_act_status='Scan the project'
M_ui_act_status_hint='the watchman'\''s full verdict'
M_ui_act_clean='Cleanup'
M_ui_act_clean_hint='tidy up everything that needs no judgement'
M_ui_act_publish='Copy off this machine'
M_ui_act_publish_hint='create a remote copy and push the save points'
M_ui_act_update='Update fraim'
M_ui_act_update_hint='bring the new version and lay it out into the harnesses'
M_ui_act_upgrade='Upgrade all projects'
M_ui_act_upgrade_hint='bring the registered projects up to this version'\''s standard'
M_ui_act_doctor='Doctor'
M_ui_act_doctor_hint='what is installed where, what has drifted'

M_ui_written_to='Written to: {file}'
M_ui_reset_done='{key} — back to the default'
M_ui_refreshed='refreshed'
M_ui_enter_back='Enter — back'

M_ui_hint_side='[↑↓] section  [Enter] open  [ctrl+p] commands  [?] help  [q] quit'
M_ui_hint_main='[↑↓] select  [Enter] open  [Esc] sections  [ctrl+p] commands  [r] refresh'
M_ui_hint_settings='[↑↓] item  [Enter] change  [d] default  [Esc] sections  [ctrl+p] commands'
M_ui_hint_reader='[↑↓] scroll  [PgUp PgDn] page  [Esc] back'
M_ui_hint_dialog='[type] search  [↑↓] select  [Enter] choose  [Esc] close'

M_ui_dlg_nothing='nothing found'
M_ui_dlg_keys='Enter choose · Esc close'
M_ui_pal_title='Commands'
M_ui_pal_section='section'
M_ui_pal_help='Help: keys'
M_ui_pal_quit='Quit'
M_ui_first_lang='Interface language'

M_ui_help_title='Keys'
M_ui_help_body='↑ ↓ or k j       move through a list
← → or Tab        between the sections and their content
Enter             open, change, run
Esc               back, close a dialog
1 … 7             straight to a section
ctrl+p or /       command palette: any action by a few letters
d                 in settings: back to the default
r                 re-read the project
?                 this help
q                 quit

The screen shows the state and changes settings. The work is the agent'\''s: tell it in words what you need.'
