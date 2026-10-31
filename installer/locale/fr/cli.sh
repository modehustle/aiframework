# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim — la couche d'\''exploitation des projets menés par des agents

Ce que vous tapez
  fraim                     l'\''écran fraim (dans un terminal) — comme fraim menu
  fraim menu                projet, tableau, backlog, décisions, réglages et langue sur un écran
  fraim status [PATH]       ce qui se passe dans le projet (--json pour les machines)
  fraim fleet [PATH]        où vit le travail : checkouts du projet et environnement de la flotte
  fraim undo [HASH]         lister les points de sauvegarde / remettre les choses comme avant
  fraim scaffold [PATH]     mettre un projet sous la gestion du système
  fraim upgrade [PATH]      mettre chaque projet du registre au standard de cette version
                            (PATH — ce projet seulement)
  fraim clean [--yes]       ranger tout ce qui se corrige sans jugement
  fraim publish [--check]   une copie du projet hors de cette machine : créer, pousser, vérifier
                            (--brief — une tâche pour que l'\''agent retire ce qui a été trouvé)
  fraim dispatch PLAN       flotte : vérifier le plan et ouvrir un build
  fraim dispatch collect BUILD  fusionner une vague dans la branche du build
  fraim dispatch accept BUILD   recette du chef d'\''orchestre : vérifier, contrôler, nettoyer, intégrer
                            run BUILD — démarrer la flotte dans l'\''environnement d'\''exécution
                            watch BUILD — ce que l'\''environnement dit des workers
                            verify BUILD SUBTASK — confronter l'\''arbre aux chemins
                            check PLAN · accept BUILD · list
  fraim mode                retirer du projet les restes de l'\''ancien mode flotte
  fraim roles [set [NAME]]  la table des rôles : ce que donne un rôle sur cette machine
                            (set — choisir l'\''agent, le modèle et l'\''effort dans une liste)
  fraim init                installer les skills / prendre en compte un nouveau harness
  fraim update [--check]    récupérer la nouvelle version et la déployer (--check — seulement
                            savoir ; --quiet — pour le démarrage auto : muet, ne gêne jamais)
  fraim doctor              ce qui est installé où, ce qui a dérivé
  fraim config              ce qui est en vigueur et d'\''où ça vient (set / unset KEY)
  fraim projects            le registre des projets (add PATH / rm PATH)

Les agents et les procédures appellent ceux-ci — inutile de les retenir'
M_cli_usage_tail='
Service
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            supprimés avec les plans : une tâche est désormais une fiche
  fraim show NAME           afficher le texte d'\''une procédure
  fraim build               reconstruire les artefacts du dépôt
  fraim version             la version
  fraim help                cet écran

La sentinelle est déterministe : fichiers, git log et mtime. Pas de modèle, pas de réseau,
et elle n'\''écrit rien. Elle remarque — l'\''humain décide.'

# Shared words.
M_cli_err_unknown_command='commande inconnue : {cmd}'
M_cli_err_unknown_flag='option inconnue : {flag}'
M_cli_err_subcommand='sous-commande inconnue : {sub}'
M_cli_err_no_dir='répertoire introuvable : {path}'
M_cli_err_no_procedures='répertoire procedures/ introuvable'
M_cli_err_need_path='indiquez un chemin'
M_cli_err_not_project='pas de ai/ ici — ce n'\''est pas un projet géré par le système (fraim scaffold)'
M_cli_registered='projet enregistré : {path}'
M_cli_context_block='bloc de contexte → {path}'
M_cli_cancelled='annulé'

# init
M_cli_init_err_broken='répertoire procedures/ introuvable — l'\''installation est endommagée'
M_cli_init_source='fraim {ver} · source : {root}'
M_cli_init_skills_built='skills construits : {n} (procédures + skill maître)'
M_cli_init_harness_failed='{label} : l'\''installation a échoué'
M_cli_init_context_failed='{label} : impossible de mettre à jour {path}'
M_cli_init_no_harness='aucun harness trouvé'
M_cli_init_no_harness_copy='les skills sont construits dans {path} — copiez-les à la main dans le répertoire de votre agent,'
M_cli_init_no_harness_rerun='ou installez un harness et relancez '\''fraim init'\'' (la commande est idempotente).'
M_cli_init_registry_count='projets dans le registre : {n} — pour les mettre au niveau de cette version : fraim upgrade'
M_cli_init_done='Terminé. Vérifiez : {cmd}'
M_cli_perm_added='permission Bash(fraim:*) ajoutée à ~/.claude/settings.json'
M_cli_perm_hint='Claude Code : ajoutez "Bash(fraim:*)" à permissions.allow dans ~/.claude/settings.json'

# update
M_cli_upd_not_clone='la source n'\''est pas un clone git — rien à vérifier'
M_cli_upd_network_hint='réseau ou accès au dépôt : vérifiez git ls-remote'
M_cli_upd_latest='la dernière version est installée ({ver})'
M_cli_upd_updated='fraim mis à jour : {from} → {to}'
M_cli_upd_err_flag='fraim update : option inconnue : {flag}'
M_cli_upd_title='Mise à jour de fraim'
M_cli_upd_was='avant : {ver}'

# status
M_cli_status_unmanaged='{path} n'\''est pas géré par le système : ni ai/ ni ARCHITECTURE.md'
M_cli_status_unmanaged_hint='faire entrer un projet existant — /onboard ; un nouveau — /design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_one='{n} tâche sur le tableau'
M_cli_fleet_on_board_other='{n} tâches sur le tableau'
M_cli_fleet_clean='propre'
M_cli_fleet_err_not_repo='{path} n'\''est pas un dépôt — il n'\''y a pas de checkouts et il ne peut pas y en avoir'
M_cli_fleet_ade_alive='{label} ({cmd}) — l'\''environnement répond'
M_cli_fleet_ade_silent='{label} ({cmd}) — installé, l'\''environnement ne répond pas'
M_cli_fleet_auto_free='{label} : un agent planifié travaille sur ce projet — assurez-vous qu'\''il ne modifie pas le code dans votre dos'
M_cli_fleet_auto_watchman='{label} : la sentinelle tourne selon un planning — c'\''est de l'\''observation, pas de la modification'
M_cli_fleet_no_ade='aucun environnement de flotte trouvé sur cette machine'

# projects
M_cli_proj_no_dir='(pas de répertoire)'
M_cli_proj_empty='le registre est vide — '\''fraim projects add PATH'\'' ou lancez '\''fraim init'\'' dans un projet'
M_cli_proj_added='ajouté : {path}'
M_cli_proj_removed='retiré : {path}'

# doctor
M_cli_doc_source_git='source : {root} ({branch} {sha}, {date})'
M_cli_doc_source='source : {root}'
M_cli_doc_state='état :   {path}'
M_cli_doc_latest='dernière version connue'
M_cli_doc_procedures='Procédures'
M_cli_doc_harnesses='Harness'
M_cli_doc_skills_ok='{n} skills, version {ver}'
M_cli_doc_skills_mismatch='{n} skills, versions : {vers}(installée {ver} — fraim init nécessaire)'
M_cli_doc_no_skills='trouvé, skills non installés — lancez fraim init'
M_cli_doc_not_found='introuvable'
M_cli_doc_registry='Registre des projets'
M_cli_doc_registry_empty='vide'
M_cli_doc_registry_count='projets : {n}'
M_cli_doc_registry_gone='le répertoire a disparu : {path}  ('\''fraim projects rm'\'' pour le retirer)'

# show, build
M_cli_show_err_need_name='indiquez un nom de procédure : {list}'
M_cli_show_err_unknown='procédure inconnue : {name}'
M_cli_build_plugin='plugin Claude Code : {n} skills'
M_cli_build_manifest='manifeste : procedures/manifest.json'

# scaffold
M_cli_scaf_title='Squelette du socle dans {path}'
M_cli_scaf_err='impossible de poser le squelette'
M_cli_scaf_registered='projet inscrit au registre'
M_cli_scaf_next='Ensuite : {bootstrap} pour un nouveau projet, {onboard} pour du code existant.'
M_cli_scaf_stub_note='Les fichiers portent le marqueur fraim:stub — tant qu'\''il est là, la sentinelle les compte comme non remplis.'

# upgrade
M_cli_upg_err_empty='le registre des projets est vide — '\''fraim upgrade PATH'\'' pour un projet ou '\''fraim init'\'' dans un projet'
M_cli_upg_skip_no_dir='pas de répertoire — ignoré ; retirez-le du registre : fraim projects rm {path}'
M_cli_upg_skip_unmanaged='non géré par le système — ignoré'
M_cli_upg_summary='Projets : mis à niveau {ok}, ignorés {skip}, en échec {fail}'
M_cli_upg_err_unmanaged='rien à mettre à niveau ici : ce n'\''est pas un projet géré par le système. Pour en créer un — fraim scaffold'
M_cli_upg_title='Mise du socle au standard de fraim {ver} dans {path}'
M_cli_upg_err_scaffold='impossible de mettre le socle à niveau'
M_cli_upg_err_sections='impossible d'\''ajouter les sections'
M_cli_upg_err_tasks='impossible de convertir les tâches à l'\''ancien format'
M_cli_upg_conf_refreshed='ai/fraim.conf — liste des réglages rafraîchie, clés supprimées retirées'
M_cli_upg_done='terminé — vérifiez : fraim status'

# version
M_cli_ver_source='source : {root}'
M_cli_ver_git='branche {branch} · commit {sha} · {date}'
M_cli_ver_not_clone='source : {root} (pas un clone git)'

# publish
M_cli_pub_err_provider_arg='--provider attend un nom'
M_cli_pub_err_url_arg='--url attend un lien'
M_cli_pub_err_name_arg='--name attend un nom'
M_cli_pub_err_flag='option inconnue : {flag} (voir fraim help)'
M_cli_pub_err_extra='argument en trop : {arg} — le nom se donne avec --name'
M_cli_pub_err_provider='fournisseur inconnu : {prov} (github, gitlab, url)'
M_cli_pub_err_no_git='git n'\''est pas installé — rien pour pousser'
M_cli_pub_err_no_repo='pas de dépôt ici — fraim scaffold en crée un'
M_cli_pub_nothing_to_clean='rien à retirer : l'\''analyse n'\''a rien trouvé'
M_cli_pub_no_commits='pas encore un seul point de sauvegarde — rien à pousser'
M_cli_pub_save_and_retry='sauvegardez le travail et réessayez : fraim clean, ou fraim commit KIND TEXT PATH...'
M_cli_pub_copy='Copie : {url}'
M_cli_pub_never_pushed='rien n'\''y a jamais été poussé — la configuration a été commencée et pas terminée'
M_cli_pub_unpushed='points de sauvegarde non poussés : {n}'
M_cli_pub_all_pushed='selon les relevés de cette machine — tout a été poussé'
M_cli_pub_host_needs_net='ce qui se trouve réellement sur l'\''hôte, fraim publish le vérifie : il faut le réseau'
M_cli_pub_no_copy='Il n'\''y a pas de copie hors de cette machine.'
M_cli_pub_risk_private='vers une copie privée, cela part en acceptant le risque (fraim publish --private),'
M_cli_pub_risk_public='vers une copie publique — non ; pour nettoyer à la place — fraim publish --brief'
M_cli_pub_asking_host='je demande à l'\''hôte ce qu'\''il contient…'
M_cli_pub_synced='la copie est en place et correspond à cette machine : {url}'
M_cli_pub_err_choice='choix non compris'
M_cli_pub_err_no_target='la destination n'\''est pas indiquée : --provider github|gitlab | --url URL'
M_cli_pub_err_no_url='sans lien, nulle part où pousser'
M_cli_pub_err_url_needed='--provider url attend un lien : --url URL'
M_cli_pub_repo_name='nom de dépôt « {name} » : les hôtes n'\''acceptent que les lettres latines, les chiffres, le point et le tiret'
M_cli_pub_vis_src_yours='d'\''après vous'
M_cli_pub_force_warn='--force : les détections ci-dessus partiront sur l'\''hôte avec l'\''historique, et c'\''est irréversible'
M_cli_pub_ask_with_findings='Publier AVEC les détections vers la copie privée ? [o/N]'
M_cli_pub_ask='Publier ? [o/N]'
M_cli_pub_plan_only='ce n'\''était que le plan. Pour l'\''exécuter : fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='rien à ranger ici : ce n'\''est pas un projet géré par le système'
M_cli_clean_ask='Commencer ? [o/N]'
M_cli_clean_plan_only='ce n'\''était que le plan. Pour l'\''exécuter : fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} n'\''existe plus : une tâche est désormais une fiche sans plan — fraim tasks, task-new, task-seal (fraim help)'
M_cli_decide_usage='usage : fraim decide "TITLE" [--supersedes "WHAT IT REPLACES"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes attend un texte'
M_cli_inv_err_slug='il faut le slug d'\''une enquête'
M_cli_commit_usage='usage : fraim commit KIND TEXT PATH... (les chemins sont obligatoires — « tout » n'\''existe pas)'
M_cli_commit_err_kind='le type doit être un seul mot en minuscules : task, deploy, onboard, archive…'
M_cli_commit_err_no_git='pas de git ici — rien où placer un point de sauvegarde'
M_cli_commit_failed='le commit a échoué'

# dispatch
M_cli_disp_usage='usage : fraim dispatch PLAN (ou check / run / watch / collect / verify / accept / list)'
M_cli_disp_usage_check='usage : fraim dispatch check PLAN'
M_cli_disp_usage_verify='usage : fraim dispatch verify BUILD SUBTASK [BASE]'
M_cli_disp_usage_run='usage : fraim dispatch run BUILD [WAVE]'
M_cli_disp_usage_watch='usage : fraim dispatch watch BUILD'
M_cli_disp_usage_collect='usage : fraim dispatch collect BUILD [WAVE]'
M_cli_disp_usage_accept='usage : fraim dispatch accept BUILD'
M_cli_disp_err_plan_bad='le plan ne convient pas à une distribution en parallèle'
M_cli_disp_check_ok='le plan passe dispatch-check'
M_cli_disp_err_no_build_plan='pas de plan pour le build {build}'
M_cli_disp_err_no_subtask='le build {build} n'\''a pas de sous-tâche {sub}'
M_cli_disp_checkout='checkout de la sous-tâche : {path}'
M_cli_disp_no_checkout='pas de checkout séparé {name} — je vérifie la racine du projet'
M_cli_disp_launching='Démarrage de la flotte pour le build {build}...'
M_cli_disp_launched='la flotte est lancée'
M_cli_disp_hint_watch='état :                fraim dispatch watch {build}'
M_cli_disp_hint_collect='collecter une vague : fraim dispatch collect {build}'
M_cli_disp_launch_partial='certains workers n'\''ont pas démarré — ceux qui ont démarré sont notés dans ai/builds/{build}/fleet.tsv'
M_cli_disp_watch_not_up='n'\''a pas démarré'
M_cli_disp_watch_unexpected='l'\''environnement a répondu autrement que prévu :'
M_cli_disp_watch_note_terminal='l'\''état du terminal n'\''est pas le statut de la tâche : une tâche terminée peut'
M_cli_disp_watch_note_verify='garder un terminal actif. Ce qui est fait — dispatch verify le montrera.'
M_cli_disp_collected='la vague est collectée dans la branche {branch}'
M_cli_disp_next_wave='vague suivante :  fraim dispatch run {build}'
M_cli_disp_next_wave_note='(vague {wave} — les workers partiront de la branche collectée)'
M_cli_disp_all_collected='toutes les vagues sont collectées — acceptez le travail de la flotte :'
M_cli_disp_accept_hint='fraim dispatch accept {build}  (vérification, contrôle global, nettoyage, rapport)'
M_cli_disp_err_collect_partial='la vague n'\''est pas entièrement collectée — traitez les rejets et réessayez'
M_cli_disp_err_accept='la recette a échoué'
M_cli_disp_accepted='build {build} accepté, contrôlé et dans la branche principale'
M_cli_disp_not_accepted='build {build} contrôlé, non intégré à la branche principale — réglez le problème et réessayez'
M_cli_disp_err_no_plan='pas de plan : {path}'
M_cli_disp_err_journal='impossible d'\''ouvrir le journal du build'
M_cli_disp_build_title='Build {build} — qui fait quoi :'
M_cli_disp_err_write_task='impossible d'\''écrire la tâche de la sous-tâche {id}'
M_cli_disp_task_written='tâche {id} → {path}'
M_cli_disp_tasks_done='tâches écrites, journal ouvert : ai/builds/{build}/journal.md'
M_cli_disp_plan_hint_run='lancer une vague :    fraim dispatch run {build}'
M_cli_disp_plan_no_ade='pas d'\''environnement d'\''exécution sur cette machine — les tâches peuvent se faire à la main'
M_cli_disp_plan_hint_collect='collecter une vague : fraim dispatch collect {build}'
M_cli_disp_plan_hint_verify='vérifier l'\''arbre :    fraim dispatch verify {build} SUBTASK'

# roles
M_cli_roles_err_form='« {value} » n'\''est pas de la forme agent:model:effort'
M_cli_roles_err_write='impossible d'\''écrire dans {path}'
M_cli_roles_err_no_tty='le choix demande un terminal — ou réglez-le directement : fraim roles set KEY agent:model:effort'
M_cli_roles_pick_key='Que réglons-nous — une classe de modèles ou une seule procédure ?'
M_cli_roles_pick_agent='Agent :'
M_cli_roles_pick_model='Modèle :'
M_cli_roles_pick_effort='Effort :'
M_cli_roles_err_result='obtenu « {value} » — ce n'\''est pas agent:model:effort'
M_cli_roles_pick_level='Où l'\''écrire ?'
M_cli_roles_level_machine='cette machine (~/.fraim/config)'
M_cli_roles_level_project='ce projet seulement (ai/fraim.conf)'
M_cli_roles_none='aucun rôle défini — tout va au défaut intégré :'
M_cli_roles_set_hint='pour en définir un : fraim config set role_refactor claude:haiku:medium'
M_cli_roles_col_role='rôle'
M_cli_roles_col_agent='agent'
M_cli_roles_col_model='modèle'
M_cli_roles_col_effort='effort'
M_cli_roles_col_source='source'

# mode
M_cli_mode_gone='il n'\''y a plus de modes : l'\''agent travaille lui-même, dans la conversation'
M_cli_mode_conductor_note='le chef d'\''orchestre et la flotte sont la procédure /conductor, lancée quand l'\''humain le demande'
M_cli_mode_err_conf='impossible de retirer la ligne mode de ai/fraim.conf'
M_cli_mode_conf_done='ligne mode retirée de ai/fraim.conf'
M_cli_mode_err_agents='impossible de mettre à jour AGENTS.md'
M_cli_mode_agents_done='bloc du chef d'\''orchestre retiré d'\''AGENTS.md'
M_cli_mode_hook_done='hook SessionStart retiré de .claude/settings.json'
M_cli_mode_hook_no_python='pas de python3 — retirez à la main le hook « {mark} » de .claude/settings.json'
M_cli_mode_hook_unreadable='impossible de lire .claude/settings.json — le hook « {mark} » est toujours là'
M_cli_mode_nothing='aucun reste de l'\''ancien mode ici'
