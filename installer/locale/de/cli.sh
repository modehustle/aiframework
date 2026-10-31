# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim — die Betriebsschicht für agentengetriebene Projekte

Das tippst du
  fraim                     der fraim-Bildschirm (im Terminal) — dasselbe wie fraim menu
  fraim menu                Projekt, Board, Backlog, Entscheidungen, Einstellungen und Sprache auf einem Bildschirm
  fraim status [PATH]       was im Projekt los ist (--json für Maschinen)
  fraim fleet [PATH]        wo die Arbeit liegt: Checkouts des Projekts und die Laufzeitumgebung der Flotte
  fraim undo [HASH]         Sicherungspunkte anzeigen / den vorherigen Stand zurückholen
  fraim scaffold [PATH]     ein Projekt ins System aufnehmen
  fraim upgrade [PATH]      alle registrierten Projekte auf den Standard dieser Version bringen
                            (PATH — nur dieses Projekt)
  fraim clean [--yes]       alles aufräumen, was sich ohne Abwägung beheben lässt
  fraim publish [--check]   eine Kopie des Projekts außerhalb dieses Rechners: anlegen, pushen, prüfen
                            (--brief — ein Auftrag an den Agenten, das Gefundene zu bereinigen)
  fraim dispatch PLAN       Flotte: den Plan prüfen und einen Build anlegen
  fraim dispatch collect BUILD  eine Welle in den Build-Branch einsammeln
  fraim dispatch accept BUILD   Abnahme durch den Dirigenten: abgleichen, prüfen, aufräumen, Trunk
                            run BUILD — die Flotte in der Laufzeitumgebung starten
                            watch BUILD — was die Laufzeitumgebung über die Worker meldet
                            verify BUILD SUBTASK — den Baum mit den Pfaden abgleichen
                            check PLAN · accept BUILD · list
  fraim mode                Reste des alten Flottenmodus aus dem Projekt entfernen
  fraim roles [set [NAME]]  die Rollentabelle: worauf eine Rolle auf diesem Rechner auflöst
                            (set — Agent, Modell und Aufwand aus einer Liste wählen)
  fraim init                die Skills installieren / einen neuen Harness übernehmen
  fraim update [--check]    die neue Version holen und ausrollen (--check — nur nachsehen;
                            --quiet — für den Autostart: still, steht nie im Weg)
  fraim doctor              was wo installiert ist, was auseinandergelaufen ist
  fraim config              was gilt und woher (set / unset KEY)
  fraim projects            die Projekt-Registry (add PATH / rm PATH)

Das rufen Agenten und Prozeduren auf — merken musst du sie dir nicht'
M_cli_usage_tail='
Intern
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            zusammen mit den Plänen entfernt: eine Aufgabe ist jetzt eine Karte
  fraim show NAME           den Text einer Prozedur ausgeben
  fraim build               die Artefakte des Repositorys neu bauen
  fraim version             die Version
  fraim help                dieser Bildschirm

Der Wächter ist deterministisch: Dateien, git log und mtime. Kein Modell, kein Netz, und er
schreibt nichts. Er bemerkt — der Mensch entscheidet.'

# Shared words.
M_cli_err_unknown_command='unbekannter Befehl: {cmd}'
M_cli_err_unknown_flag='unbekannte Option: {flag}'
M_cli_err_subcommand='unbekannter Unterbefehl: {sub}'
M_cli_err_no_dir='Verzeichnis nicht gefunden: {path}'
M_cli_err_no_procedures='Verzeichnis procedures/ nicht gefunden'
M_cli_err_need_path='gib einen Pfad an'
M_cli_err_not_project='hier gibt es kein ai/ — das ist kein Projekt im System (fraim scaffold)'
M_cli_registered='Projekt registriert: {path}'
M_cli_context_block='Kontextblock → {path}'
M_cli_cancelled='abgebrochen'

# init
M_cli_init_err_broken='Verzeichnis procedures/ nicht gefunden — die Installation ist beschädigt'
M_cli_init_source='fraim {ver} · Quelle: {root}'
M_cli_init_skills_built='Skills gebaut: {n} (Prozeduren + Master-Skill)'
M_cli_init_harness_dir_failed='{label}: Installation nach {dir} fehlgeschlagen'
M_cli_init_swept='vom alten Ort entfernt: {path}'
M_cli_init_context_failed='{label}: {path} konnte nicht aktualisiert werden'
M_cli_init_no_harness='kein Harness gefunden'
M_cli_init_no_harness_copy='die Skills liegen in {path} — kopiere sie von Hand in das Verzeichnis deines Agenten,'
M_cli_init_no_harness_rerun='oder installiere einen Harness und führe '\''fraim init'\'' erneut aus (der Befehl ist idempotent).'
M_cli_init_registry_count='Projekte in der Registry: {n} — auf diese Version bringen: fraim upgrade'
M_cli_init_done='Fertig. Prüfen: {cmd}'
M_cli_perm_added='Berechtigung Bash(fraim:*) zu ~/.claude/settings.json hinzugefügt'
M_cli_perm_hint='Claude Code: füge "Bash(fraim:*)" zu permissions.allow in ~/.claude/settings.json hinzu'

# update
M_cli_upd_not_clone='die Quelle ist kein git-Klon — nichts zu prüfen'
M_cli_upd_network_hint='Netz oder Zugriff auf das Repository: prüfe git ls-remote'
M_cli_upd_latest='die neueste Version ist installiert ({ver})'
M_cli_upd_updated='fraim aktualisiert: {from} → {to}'
M_cli_upd_err_flag='fraim update: unbekannte Option: {flag}'
M_cli_upd_title='fraim wird aktualisiert'
M_cli_upd_was='vorher: {ver}'

# status
M_cli_status_unmanaged='{path} ist nicht im System: weder ai/ noch ARCHITECTURE.md'
M_cli_status_unmanaged_hint='ein bestehendes Projekt aufnehmen — /onboard; ein neues — /design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_one='{n} Aufgabe auf dem Board'
M_cli_fleet_on_board_other='{n} Aufgaben auf dem Board'
M_cli_fleet_clean='sauber'
M_cli_fleet_err_not_repo='{path} ist kein Repository — Checkouts gibt es nicht und kann es nicht geben'

# projects
M_cli_proj_no_dir='(kein Verzeichnis)'
M_cli_proj_empty='die Registry ist leer — '\''fraim projects add PATH'\'' oder '\''fraim init'\'' in einem Projekt ausführen'
M_cli_proj_added='hinzugefügt: {path}'
M_cli_proj_removed='entfernt: {path}'

# doctor
M_cli_doc_source_git='Quelle:  {root} ({branch} {sha}, {date})'
M_cli_doc_source='Quelle:  {root}'
M_cli_doc_state='Zustand: {path}'
M_cli_doc_latest='neueste bekannte Version'
M_cli_doc_procedures='Prozeduren'
M_cli_doc_harnesses='Harnesses'
M_cli_doc_skills_ok='{n} Skills, Version {ver}'
M_cli_doc_skills_mismatch='{n} Skills, Versionen: {vers}(installiert {ver} — fraim init nötig)'
M_cli_doc_no_skills='gefunden, Skills nicht installiert — führe fraim init aus'
M_cli_doc_not_found='nicht gefunden'
M_cli_doc_registry='Projekt-Registry'
M_cli_doc_registry_empty='leer'
M_cli_doc_registry_count='Projekte: {n}'
M_cli_doc_registry_gone='Verzeichnis verschwunden: {path}  ('\''fraim projects rm'\'' zum Entfernen)'

# show, build
M_cli_show_err_need_name='gib einen Prozedurnamen an: {list}'
M_cli_show_err_unknown='keine solche Prozedur: {name}'
M_cli_build_plugin='Claude-Code-Plugin: {n} Skills'
M_cli_build_manifest='Manifest: procedures/manifest.json'

# scaffold
M_cli_scaf_title='Fundament-Skelett in {path}'
M_cli_scaf_err='das Skelett konnte nicht angelegt werden'
M_cli_scaf_registered='Projekt in der Registry eingetragen'
M_cli_scaf_next='Weiter: {bootstrap} für ein neues Projekt, {onboard} für bestehenden Code.'
M_cli_scaf_stub_note='Die Dateien tragen die Markierung fraim:stub — solange sie da ist, zählt der Wächter sie als nicht ausgefüllt.'

# upgrade
M_cli_upg_err_empty='die Projekt-Registry ist leer — '\''fraim upgrade PATH'\'' für ein Projekt oder '\''fraim init'\'' in einem Projekt'
M_cli_upg_skip_no_dir='kein Verzeichnis — übersprungen; aus der Registry entfernen: fraim projects rm {path}'
M_cli_upg_skip_unmanaged='nicht im System — übersprungen'
M_cli_upg_summary='Projekte: aktualisiert {ok}, übersprungen {skip}, fehlgeschlagen {fail}'
M_cli_upg_err_unmanaged='hier gibt es nichts zu aktualisieren: das ist kein Projekt im System. Aufnehmen — fraim scaffold'
M_cli_upg_title='Fundament in {path} wird auf den Standard von fraim {ver} gebracht'
M_cli_upg_err_scaffold='das Fundament konnte nicht aktualisiert werden'
M_cli_upg_err_sections='die Abschnitte konnten nicht ergänzt werden'
M_cli_upg_err_tasks='die Aufgaben im alten Format konnten nicht umgewandelt werden'
M_cli_upg_conf_refreshed='ai/fraim.conf — Liste der Einstellungen aufgefrischt, entfernte Schlüssel gestrichen'
M_cli_upg_done='fertig — prüfen: fraim status'

# version
M_cli_ver_source='Quelle: {root}'
M_cli_ver_git='Branch {branch} · Commit {sha} · {date}'
M_cli_ver_not_clone='Quelle: {root} (kein git-Klon)'

# publish
M_cli_pub_err_provider_arg='--provider braucht einen Namen'
M_cli_pub_err_url_arg='--url braucht einen Link'
M_cli_pub_err_name_arg='--name braucht einen Namen'
M_cli_pub_err_flag='unbekannte Option: {flag} (siehe fraim help)'
M_cli_pub_err_extra='überzähliges Argument: {arg} — der Name wird mit --name angegeben'
M_cli_pub_err_provider='unbekannter Anbieter: {prov} (github, gitlab, url)'
M_cli_pub_err_no_git='git ist nicht installiert — ohne git kein Push'
M_cli_pub_err_no_repo='hier gibt es kein Repository — fraim scaffold legt eins an'
M_cli_pub_nothing_to_clean='nichts zu bereinigen: die Prüfung hat nichts gefunden'
M_cli_pub_no_commits='noch kein einziger Sicherungspunkt — nichts zu pushen'
M_cli_pub_save_and_retry='sichere die Arbeit und versuche es erneut: fraim clean oder fraim commit KIND TEXT PATH...'
M_cli_pub_copy='Kopie: {url}'
M_cli_pub_never_pushed='dorthin wurde noch nie etwas gepusht — die Einrichtung wurde begonnen und nicht abgeschlossen'
M_cli_pub_unpushed='nicht gepushte Sicherungspunkte: {n}'
M_cli_pub_all_pushed='laut den Aufzeichnungen dieses Rechners ist alles gepusht'
M_cli_pub_host_needs_net='was tatsächlich auf dem Host liegt, prüft fraim publish: dafür braucht es das Netz'
M_cli_pub_no_copy='Es gibt keine Kopie außerhalb dieses Rechners.'
M_cli_pub_risk_private='in eine private Kopie geht das nur mit akzeptiertem Risiko (fraim publish --private),'
M_cli_pub_risk_public='in eine öffentliche gar nicht; stattdessen bereinigen — fraim publish --brief'
M_cli_pub_asking_host='frage den Host, was dort liegt…'
M_cli_pub_synced='die Kopie ist da und stimmt mit diesem Rechner überein: {url}'
M_cli_pub_err_choice='Auswahl nicht verstanden'
M_cli_pub_err_no_target='nicht angegeben, wohin veröffentlicht werden soll: --provider github|gitlab | --url LINK'
M_cli_pub_err_no_url='ohne Link gibt es kein Ziel für den Push'
M_cli_pub_err_url_needed='--provider url braucht einen Link: --url LINK'
M_cli_pub_repo_name='Repository-Name «{name}»: Hosts akzeptieren nur lateinische Buchstaben, Ziffern, Punkt und Bindestrich'
M_cli_pub_vis_src_yours='nach deiner Angabe'
M_cli_pub_force_warn='--force: die Befunde oben gehen zusammen mit der Historie auf den Host, und das lässt sich nicht rückgängig machen'
M_cli_pub_ask_with_findings='MIT den Befunden in die private Kopie veröffentlichen? [j/N]'
M_cli_pub_ask='Veröffentlichen? [j/N]'
M_cli_pub_plan_only='das war nur der Plan. Ausführen: fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='hier gibt es nichts aufzuräumen: das ist kein Projekt im System'
M_cli_clean_ask='Starten? [j/N]'
M_cli_clean_plan_only='das war nur der Plan. Ausführen: fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} gibt es nicht mehr: eine Aufgabe ist jetzt eine Karte ohne Plan — fraim tasks, task-new, task-seal (fraim help)'
M_cli_decide_usage='Aufruf: fraim decide "TITLE" [--supersedes "WHAT IT REPLACES"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes braucht einen Text'
M_cli_inv_err_slug='ein Slug für die Untersuchung wird benötigt'
M_cli_commit_usage='Aufruf: fraim commit KIND TEXT PATH... (Pfade sind Pflicht — «alles» gibt es nicht)'
M_cli_commit_err_kind='die Art muss ein einzelnes kleingeschriebenes Wort sein: task, deploy, onboard, archive…'
M_cli_commit_err_no_git='hier gibt es kein git — ein Sicherungspunkt hätte keinen Ort'
M_cli_commit_failed='der Commit ist fehlgeschlagen'

# dispatch
M_cli_disp_usage='Aufruf: fraim dispatch PLAN (oder check / prepare / collect / verify / accept / list)'
M_cli_disp_usage_check='Aufruf: fraim dispatch check PLAN'
M_cli_disp_usage_verify='Aufruf: fraim dispatch verify BUILD SUBTASK [BRANCH]'
M_cli_disp_usage_collect='Aufruf: fraim dispatch collect BUILD [SUBTASK=BRANCH …]'
M_cli_disp_usage_accept='Aufruf: fraim dispatch accept BUILD'
M_cli_disp_err_plan_bad='der Plan eignet sich nicht für parallele Verteilung'
M_cli_disp_check_ok='der Plan besteht dispatch-check'
M_cli_disp_err_no_build_plan='kein Plan für Build {build}'
M_cli_disp_err_no_subtask='Build {build} hat keine Teilaufgabe {sub}'
M_cli_disp_hint_collect='Runde einsammeln:  fraim dispatch collect {build} [SUBTASK=BRANCH …]'
M_cli_disp_collected='die Runde ist in Branch {branch} eingesammelt'
M_cli_disp_accept_hint='fraim dispatch accept {build}  (Abgleich, Master-Prüfung, Aufräumen, Bericht)'
M_cli_disp_err_collect_partial='die Runde ist nicht vollständig eingesammelt — kümmere dich um die abgelehnten und versuche es erneut'
M_cli_disp_err_accept='die Abnahme ist fehlgeschlagen'
M_cli_disp_accepted='Build {build} abgenommen, geprüft und im Trunk'
M_cli_disp_not_accepted='Build {build} geprüft, aber nicht in den Trunk übernommen — kläre das und versuche es erneut'
M_cli_disp_err_no_plan='kein Plan: {path}'
M_cli_disp_err_journal='das Build-Journal konnte nicht angelegt werden'
M_cli_disp_build_title='Build {build} — wer macht was:'
M_cli_disp_plan_hint_verify='ein Ergebnis prüfen:  fraim dispatch verify {build} SUBTASK [BRANCH]'

# roles

# mode
M_cli_mode_gone='Modi gibt es nicht mehr: der Agent arbeitet selbst, im Gespräch'
M_cli_mode_conductor_note='Dirigent und Flotte sind die Prozedur /conductor, gestartet, wenn der Mensch darum bittet'
M_cli_mode_err_conf='die mode-Zeile konnte nicht aus ai/fraim.conf entfernt werden'
M_cli_mode_conf_done='mode-Zeile aus ai/fraim.conf entfernt'
M_cli_mode_err_agents='AGENTS.md konnte nicht aktualisiert werden'
M_cli_mode_agents_done='Dirigenten-Block aus AGENTS.md entfernt'
M_cli_mode_hook_done='SessionStart-Hook aus .claude/settings.json entfernt'
M_cli_mode_hook_no_python='kein python3 — entferne den Hook «{mark}» von Hand aus .claude/settings.json'
M_cli_mode_hook_unreadable='.claude/settings.json konnte nicht gelesen werden — der Hook «{mark}» ist noch da'
M_cli_mode_nothing='hier gibt es keine Reste des alten Modus'
M_cli_disp_usage_prepare='Aufruf: fraim dispatch prepare BUILD'
M_cli_disp_retired='fraim dispatch {verb} gibt es nicht mehr: Worker startet dein Harness mit seinen eigenen Subagenten (/conductor, Schritt 4); Checkouts für ein Harness ohne Isolation — fraim dispatch prepare BUILD'
M_cli_retired_roles='fraim roles gibt es nicht mehr: Worker laufen auf dem Modell des Agenten selbst, außer der Mensch nennt in Worten ein anderes'
M_cli_disp_preparing='Checkouts für Build {build}:'
M_cli_disp_err_prepare='nicht alle Checkouts wurden angelegt — siehe oben'
M_cli_disp_hint_spawn_prepared='ein Subagent pro Checkout: er arbeitet dort und liest sein Briefing'
M_cli_disp_err_no_result='kein Ergebnis für Teilaufgabe {sub}: nenne ihren Branch oder bereite einen Checkout vor'
M_cli_disp_err_write_brief='das Briefing von Teilaufgabe {id} ließ sich nicht schreiben'
M_cli_disp_brief_written='Briefing {id} → {path}'
M_cli_disp_briefs_done='Briefings geschrieben, Journal angelegt: ai/builds/{build}/journal.md'
M_cli_disp_hint_spawn='starte einen Subagenten pro Briefing, jeden in seinem eigenen Worktree (die Isolation deines Harness)'
M_cli_disp_hint_prepare='dein Harness hat keine Isolation:  fraim dispatch prepare {build}'
