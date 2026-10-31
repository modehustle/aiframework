# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim — la capa operativa para proyectos llevados por agentes

Esto lo escribes tú
  fraim                     la pantalla de fraim (en un terminal) — igual que fraim menu
  fraim menu                proyecto, tablero, backlog, decisiones, ajustes e idioma en una pantalla
  fraim status [RUTA]       qué está pasando en el proyecto (--json para máquinas)
  fraim fleet [RUTA]        dónde vive el trabajo: los checkouts del proyecto
  fraim undo [HASH]         listar los puntos de guardado / dejar las cosas como estaban
  fraim scaffold [RUTA]     poner un proyecto bajo el sistema
  fraim upgrade [RUTA]      poner al día cada proyecto registrado con el estándar de esta versión
                            (RUTA — solo este proyecto)
  fraim clean [--yes]       ordenar todo lo que se arregla sin necesidad de criterio
  fraim publish [--check]   una copia del proyecto fuera de esta máquina: crear, enviar, verificar
                            (--brief — una tarea para que el agente limpie lo encontrado)
  fraim dispatch PLAN       flota: comprobar el plan y abrir un build
  fraim dispatch collect BUILD  fusionar los resultados de la ronda en la rama del build
  fraim dispatch accept BUILD   la aceptación del director: verificar, comprobar, limpiar, rama principal
                            prepare BUILD — checkouts para un harness sin aislamiento
                            verify BUILD SUBTAREA [RAMA] — un resultado frente a sus rutas
                            check PLAN · list
  fraim mode                quitar del proyecto los restos del antiguo modo flota
  fraim init                instalar las skills / detectar un harness nuevo
  fraim update [--check]    traer la versión nueva y desplegarla (--check — solo averiguar;
                            --quiet — para el arranque automático: en silencio, nunca estorba)
  fraim doctor              qué está instalado y dónde, qué se ha desviado
  fraim config              qué está en vigor y de dónde viene (set / unset CLAVE)
  fraim projects            el registro de proyectos (add RUTA / rm RUTA)

Esto lo llaman los agentes y los procedimientos — no hace falta que lo recuerdes'
M_cli_usage_tail='
Utilidades
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            eliminados junto con los planes: ahora una tarea es una tarjeta
  fraim roles               eliminado junto con la tabla de roles: un worker usa el modelo del propio agente
  fraim show NOMBRE         mostrar el texto de un procedimiento
  fraim build               reconstruir los artefactos del repositorio
  fraim version             la versión
  fraim help                esta pantalla

El vigilante es determinista: archivos, git log y mtime. Sin modelo, sin red, y no
escribe nada. Él avisa — la persona decide.'

# Shared words.
M_cli_err_unknown_command='comando desconocido: {cmd}'
M_cli_err_unknown_flag='opción desconocida: {flag}'
M_cli_err_subcommand='subcomando desconocido: {sub}'
M_cli_err_no_dir='no existe el directorio: {path}'
M_cli_err_no_procedures='no se encontró el directorio procedures/'
M_cli_err_need_path='indica una ruta'
M_cli_err_not_project='aquí no hay ai/ — no es un proyecto bajo el sistema (fraim scaffold)'
M_cli_registered='proyecto registrado: {path}'
M_cli_context_block='bloque de contexto → {path}'
M_cli_cancelled='cancelado'

# init
M_cli_init_err_broken='no se encontró el directorio procedures/ — la instalación está dañada'
M_cli_init_source='fraim {ver} · origen: {root}'
M_cli_init_skills_built='skills generadas: {n} (procedimientos + skill maestra)'
M_cli_init_harness_dir_failed='{label}: falló la instalación en {dir}'
M_cli_init_swept='retirado de su ubicación anterior: {path}'
M_cli_init_context_failed='{label}: no se pudo actualizar {path}'
M_cli_init_no_harness='no se encontró ningún harness'
M_cli_init_no_harness_copy='las skills están generadas en {path} — cópialas a mano en el directorio de tu agente,'
M_cli_init_no_harness_rerun='o instala un harness y vuelve a ejecutar '\''fraim init'\'' (el comando es idempotente).'
M_cli_init_registry_count='proyectos en el registro: {n} — ponlos al día con esta versión: fraim upgrade'
M_cli_init_done='Hecho. Comprueba: {cmd}'
M_cli_perm_added='permiso Bash(fraim:*) añadido a ~/.claude/settings.json'
M_cli_perm_hint='Claude Code: añade "Bash(fraim:*)" a permissions.allow en ~/.claude/settings.json'

# update
M_cli_upd_not_clone='el origen no es un clon de git — no hay nada que comprobar'
M_cli_upd_network_hint='red o acceso al repositorio: comprueba git ls-remote'
M_cli_upd_latest='está instalada la última versión ({ver})'
M_cli_upd_updated='fraim actualizado: {from} → {to}'
M_cli_upd_err_flag='fraim update: opción desconocida: {flag}'
M_cli_upd_title='Actualizando fraim'
M_cli_upd_was='antes: {ver}'

# status
M_cli_status_unmanaged='{path} no está bajo el sistema: no hay ni ai/ ni ARCHITECTURE.md'
M_cli_status_unmanaged_hint='para traer un proyecto existente — /onboard; uno nuevo — /design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_one='{n} tarea en el tablero'
M_cli_fleet_on_board_other='{n} tareas en el tablero'
M_cli_fleet_clean='limpio'
M_cli_fleet_err_not_repo='{path} no es un repositorio — no hay checkouts ni puede haberlos'

# projects
M_cli_proj_no_dir='(sin directorio)'
M_cli_proj_empty='el registro está vacío — '\''fraim projects add RUTA'\'' o ejecuta '\''fraim init'\'' en un proyecto'
M_cli_proj_added='añadido: {path}'
M_cli_proj_removed='quitado: {path}'

# doctor
M_cli_doc_source_git='origen: {root} ({branch} {sha}, {date})'
M_cli_doc_source='origen: {root}'
M_cli_doc_state='estado: {path}'
M_cli_doc_latest='última versión conocida'
M_cli_doc_procedures='Procedimientos'
M_cli_doc_harnesses='Harnesses'
M_cli_doc_skills_ok='{n} skills, versión {ver}'
M_cli_doc_skills_mismatch='{n} skills, versiones: {vers}(instalada {ver} — hace falta fraim init)'
M_cli_doc_no_skills='encontrado, skills sin instalar — ejecuta fraim init'
M_cli_doc_not_found='no encontrado'
M_cli_doc_registry='Registro de proyectos'
M_cli_doc_registry_empty='vacío'
M_cli_doc_registry_count='proyectos: {n}'
M_cli_doc_registry_gone='el directorio ya no existe: {path}  ('\''fraim projects rm'\'' para quitarlo)'

# show, build
M_cli_show_err_need_name='indica el nombre de un procedimiento: {list}'
M_cli_show_err_unknown='no existe el procedimiento: {name}'
M_cli_build_plugin='plugin de Claude Code: {n} skills'
M_cli_build_manifest='manifiesto: procedures/manifest.json'

# scaffold
M_cli_scaf_title='Esqueleto de los cimientos en {path}'
M_cli_scaf_err='no se pudo crear el esqueleto'
M_cli_scaf_registered='proyecto añadido al registro'
M_cli_scaf_next='Siguiente: {bootstrap} para un proyecto nuevo, {onboard} para código existente.'
M_cli_scaf_stub_note='Los archivos llevan el marcador fraim:stub — mientras siga ahí, el vigilante los cuenta como sin rellenar.'

# upgrade
M_cli_upg_err_empty='el registro de proyectos está vacío — '\''fraim upgrade RUTA'\'' para un proyecto o '\''fraim init'\'' dentro de un proyecto'
M_cli_upg_skip_no_dir='no hay directorio — omitido; quítalo del registro: fraim projects rm {path}'
M_cli_upg_skip_unmanaged='no está bajo el sistema — omitido'
M_cli_upg_summary='Proyectos: puestos al día {ok}, omitidos {skip}, con error {fail}'
M_cli_upg_err_unmanaged='aquí no hay nada que poner al día: no es un proyecto bajo el sistema. Para empezar uno — fraim scaffold'
M_cli_upg_title='Poniendo los cimientos al día con el estándar de fraim {ver} en {path}'
M_cli_upg_err_scaffold='no se pudieron poner al día los cimientos'
M_cli_upg_err_sections='no se pudieron añadir las secciones'
M_cli_upg_err_tasks='no se pudieron convertir las tareas del formato antiguo'
M_cli_upg_conf_refreshed='ai/fraim.conf — lista de ajustes renovada, claves retiradas eliminadas'
M_cli_upg_done='hecho — comprueba: fraim status'

# version
M_cli_ver_source='origen: {root}'
M_cli_ver_git='rama {branch} · commit {sha} · {date}'
M_cli_ver_not_clone='origen: {root} (no es un clon de git)'

# publish
M_cli_pub_err_provider_arg='--provider necesita un nombre'
M_cli_pub_err_url_arg='--url necesita un enlace'
M_cli_pub_err_name_arg='--name necesita un nombre'
M_cli_pub_err_flag='opción desconocida: {flag} (ver fraim help)'
M_cli_pub_err_extra='argumento de más: {arg} — el nombre se da con --name'
M_cli_pub_err_provider='proveedor desconocido: {prov} (github, gitlab, url)'
M_cli_pub_err_no_git='git no está instalado — no hay con qué enviar'
M_cli_pub_err_no_repo='aquí no hay repositorio — fraim scaffold crea uno'
M_cli_pub_nothing_to_clean='no hay nada que limpiar: la revisión no encontró nada'
M_cli_pub_no_commits='todavía no hay ni un punto de guardado — no hay nada que enviar'
M_cli_pub_save_and_retry='guarda el trabajo y vuelve a intentarlo: fraim clean, o fraim commit TIPO TEXTO RUTA...'
M_cli_pub_copy='Copia: {url}'
M_cli_pub_never_pushed='nunca se envió nada allí — la configuración se empezó y no se terminó'
M_cli_pub_unpushed='puntos de guardado sin enviar: {n}'
M_cli_pub_all_pushed='según los registros de esta máquina — todo está enviado'
M_cli_pub_host_needs_net='lo que hay realmente en el host lo comprueba fraim publish: eso requiere red'
M_cli_pub_no_copy='No hay copia fuera de esta máquina.'
M_cli_pub_risk_private='a una copia privada esto va con el riesgo aceptado (fraim publish --private),'
M_cli_pub_risk_public='a una pública — no; para limpiarlo en su lugar — fraim publish --brief'
M_cli_pub_asking_host='preguntando al host qué hay allí…'
M_cli_pub_synced='la copia está en su sitio y coincide con esta máquina: {url}'
M_cli_pub_err_choice='no entendí la opción'
M_cli_pub_err_no_target='no se indicó dónde publicar: --provider github|gitlab | --url ENLACE'
M_cli_pub_err_no_url='sin enlace no hay adónde enviar'
M_cli_pub_err_url_needed='--provider url necesita un enlace: --url ENLACE'
M_cli_pub_repo_name='nombre de repositorio «{name}»: los hosts solo aceptan letras latinas, dígitos, punto y guion'
M_cli_pub_vis_src_yours='según dices tú'
M_cli_pub_force_warn='--force: los hallazgos de arriba irán al host junto con el historial, y eso no se puede deshacer'
M_cli_pub_ask_with_findings='¿Publicar CON los hallazgos en la copia privada? [s/N]'
M_cli_pub_ask='¿Publicar? [s/N]'
M_cli_pub_plan_only='eso era solo el plan. Para ejecutarlo: fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='aquí no hay nada que limpiar: no es un proyecto bajo el sistema'
M_cli_clean_ask='¿Empezar? [s/N]'
M_cli_clean_plan_only='eso era solo el plan. Para ejecutarlo: fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} ya no existe: ahora una tarea es una tarjeta sin plan — fraim tasks, task-new, task-seal (fraim help)'
M_cli_decide_usage='uso: fraim decide "TÍTULO" [--supersedes "LO QUE SUSTITUYE"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes necesita un texto'
M_cli_inv_err_slug='hace falta el slug de la investigación'
M_cli_commit_usage='uso: fraim commit TIPO TEXTO RUTA... (las rutas son obligatorias — no existe «todo»)'
M_cli_commit_err_kind='el tipo debe ser una sola palabra en minúsculas: task, deploy, onboard, archive…'
M_cli_commit_err_no_git='aquí no hay git — no hay dónde poner un punto de guardado'
M_cli_commit_failed='el commit falló'

# dispatch
M_cli_disp_usage='uso: fraim dispatch PLAN (o check / prepare / collect / verify / accept / list)'
M_cli_disp_usage_check='uso: fraim dispatch check PLAN'
M_cli_disp_usage_verify='uso: fraim dispatch verify BUILD SUBTAREA [RAMA]'
M_cli_disp_usage_collect='uso: fraim dispatch collect BUILD [SUBTAREA=RAMA …]'
M_cli_disp_usage_accept='uso: fraim dispatch accept BUILD'
M_cli_disp_err_plan_bad='el plan no sirve para un reparto en paralelo'
M_cli_disp_check_ok='el plan pasa dispatch-check'
M_cli_disp_err_no_build_plan='no hay plan para el build {build}'
M_cli_disp_err_no_subtask='el build {build} no tiene la subtarea {sub}'
M_cli_disp_hint_collect='recoger la ronda:  fraim dispatch collect {build} [SUBTAREA=RAMA …]'
M_cli_disp_collected='la ronda está recogida en la rama {branch}'
M_cli_disp_accept_hint='fraim dispatch accept {build}  (verificación, comprobación maestra, limpieza, informe)'
M_cli_disp_err_collect_partial='la ronda no está recogida del todo — resuelve las rechazadas y vuelve a intentarlo'
M_cli_disp_err_accept='la aceptación falló'
M_cli_disp_accepted='build {build} aceptado, comprobado y en la rama principal'
M_cli_disp_not_accepted='build {build} comprobado, no se llevó a la rama principal — resuélvelo y vuelve a intentarlo'
M_cli_disp_err_no_plan='no hay plan: {path}'
M_cli_disp_err_journal='no se pudo abrir el diario del build'
M_cli_disp_build_title='Build {build} — quién hace qué:'
M_cli_disp_plan_hint_verify='revisar un resultado:  fraim dispatch verify {build} SUBTAREA [RAMA]'

# roles

# mode
M_cli_mode_gone='ya no hay modos: el agente trabaja por sí mismo, en la conversación'
M_cli_mode_conductor_note='el director y la flota son el procedimiento /conductor, que se inicia cuando la persona lo pide'
M_cli_mode_err_conf='no se pudo quitar la línea mode de ai/fraim.conf'
M_cli_mode_conf_done='línea mode quitada de ai/fraim.conf'
M_cli_mode_err_agents='no se pudo actualizar AGENTS.md'
M_cli_mode_agents_done='bloque del director quitado de AGENTS.md'
M_cli_mode_hook_done='hook SessionStart quitado de .claude/settings.json'
M_cli_mode_hook_no_python='no hay python3 — quita a mano el hook «{mark}» de .claude/settings.json'
M_cli_mode_hook_unreadable='no se pudo leer .claude/settings.json — el hook «{mark}» sigue ahí'
M_cli_mode_nothing='aquí no hay restos del modo antiguo'
M_cli_disp_usage_prepare='uso: fraim dispatch prepare BUILD'
M_cli_disp_retired='fraim dispatch {verb} ya no existe: los workers los levantan los propios subagentes de tu harness (/conductor, paso 4); checkouts para un harness sin aislamiento — fraim dispatch prepare BUILD'
M_cli_retired_roles='fraim roles ya no existe: los workers usan el modelo del propio agente, salvo que la persona nombre otro con palabras'
M_cli_disp_preparing='Checkouts del build {build}:'
M_cli_disp_err_prepare='no se crearon todos los checkouts — ver arriba'
M_cli_disp_hint_spawn_prepared='un subagente por checkout: trabaja ahí y lee su brief'
M_cli_disp_err_no_result='no hay resultado de la subtarea {sub}: nombre su rama o prepare un checkout'
M_cli_disp_err_write_brief='no se pudo escribir el brief de la subtarea {id}'
M_cli_disp_brief_written='brief {id} → {path}'
M_cli_disp_briefs_done='briefs escritos, diario abierto: ai/builds/{build}/journal.md'
M_cli_disp_hint_spawn='levante un subagente por brief, cada uno en su propio worktree (el aislamiento de su harness)'
M_cli_disp_hint_prepare='su harness no tiene aislamiento:  fraim dispatch prepare {build}'
