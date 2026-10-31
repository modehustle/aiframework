# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim — эксплуатационный слой для проектов на агентах

Это набираешь ты
  fraim                     экран fraim (в терминале) — то же, что fraim menu
  fraim menu                проект, доска, бэклог, решения, настройки и язык на одном экране
  fraim status [ПУТЬ]       что происходит в проекте (--json для машины)
  fraim fleet [ПУТЬ]        где живёт работа: чекауты проекта
  fraim undo [ХЕШ]          показать точки сохранения / вернуть, как было
  fraim scaffold [ПУТЬ]     завести проект под систему
  fraim upgrade [ПУТЬ]      довести все проекты реестра до стандарта этой версии
                            (ПУТЬ — только этот проект)
  fraim clean [--yes]       прибрать всё, что чинится без суждения
  fraim publish [--check]   копия проекта вне этой машины: создать, отправить, сверить
                            (--brief — задание агенту вычистить найденное)
  fraim dispatch ПЛАН       флот: проверить план и завести сборку
  fraim dispatch collect СБОРКА  свести результаты круга в ветку сборки
  fraim dispatch accept СБОРКА   приёмка дирижёра: сверка, проверка, чистка, ствол
                            prepare СБОРКА — чекауты для харнеса без изоляции
                            verify СБОРКА ПОДЗАДАЧА [ВЕТКА] — один результат против его путей
                            check ПЛАН · list
  fraim mode                убрать остатки старого режима флота из проекта
  fraim init                поставить скиллы / подхватить новый харнес
  fraim update [--check]    привезти новую версию и разложить (--check — только узнать;
                            --quiet — для автозапуска: молча, и никогда не мешает старту)
  fraim doctor              что и куда установлено, что разошлось
  fraim config              что действует и откуда (set / unset КЛЮЧ)
  fraim projects            реестр проектов (add ПУТЬ / rm ПУТЬ)

Это зовут агенты и процедуры — тебе их помнить не нужно'
M_cli_usage_tail='
Служебное
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            удалены вместе с планами: задача теперь карточка
  fraim roles               убрана вместе с таблицей ролей: воркер работает на модели самого агента
  fraim show ИМЯ            напечатать текст процедуры
  fraim build               пересобрать артефакты репозитория
  fraim version             версия
  fraim help                этот экран

Сторож детерминированный: файлы, git log и mtime. Ни модели, ни сети, ничего
не пишет. Он замечает — решает человек.'

# Shared words.
M_cli_err_unknown_command='неизвестная команда: {cmd}'
M_cli_err_unknown_flag='неизвестный флаг: {flag}'
M_cli_err_subcommand='неизвестная подкоманда: {sub}'
M_cli_err_no_dir='нет такого каталога: {path}'
M_cli_err_no_procedures='не найден каталог procedures/'
M_cli_err_need_path='укажи путь'
M_cli_err_not_project='здесь нет ai/ — это не проект под системой (fraim scaffold)'
M_cli_registered='проект зарегистрирован: {path}'
M_cli_context_block='контекстный блок → {path}'
M_cli_cancelled='отменено'

# init
M_cli_init_err_broken='не найден каталог procedures/ — установка повреждена'
M_cli_init_source='fraim {ver} · источник: {root}'
M_cli_init_skills_built='собрано скиллов: {n} (процедуры + мастер-скилл)'
M_cli_init_harness_dir_failed='{label}: установка в {dir} не удалась'
M_cli_init_swept='убрано с прежнего места: {path}'
M_cli_init_context_failed='{label}: не удалось обновить {path}'
M_cli_init_no_harness='ни один харнес не найден'
M_cli_init_no_harness_copy='скиллы собраны в {path} — скопируй их в каталог своего агента вручную,'
M_cli_init_no_harness_rerun='или установи харнес и запусти '\''fraim init'\'' ещё раз (команда идемпотентна).'
M_cli_init_registry_count='проектов в реестре: {n} — довести их до этой версии: fraim upgrade'
M_cli_init_done='Готово. Проверить: {cmd}'
M_cli_perm_added='разрешение Bash(fraim:*) добавлено в ~/.claude/settings.json'
M_cli_perm_hint='Claude Code: добавь "Bash(fraim:*)" в permissions.allow в ~/.claude/settings.json'

# update
M_cli_upd_not_clone='источник — не git-клон, проверять нечего'
M_cli_upd_network_hint='сеть или доступ к репозиторию: проверь git ls-remote'
M_cli_upd_latest='установлена последняя версия ({ver})'
M_cli_upd_updated='fraim обновлён: {from} → {to}'
M_cli_upd_err_flag='fraim update: неизвестный ключ: {flag}'
M_cli_upd_title='Обновление fraim'
M_cli_upd_was='было: {ver}'

# status
M_cli_status_unmanaged='{path} не под системой: нет ни ai/, ни ARCHITECTURE.md'
M_cli_status_unmanaged_hint='завести существующий проект — /onboard; новый — /design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_one='{n} задача на доске'
M_cli_fleet_on_board_few='{n} задачи на доске'
M_cli_fleet_on_board_many='{n} задач на доске'
M_cli_fleet_clean='чисто'
M_cli_fleet_err_not_repo='{path} не репозиторий — чекаутов нет и быть не может'

# projects
M_cli_proj_no_dir='(нет каталога)'
M_cli_proj_empty='реестр пуст — '\''fraim projects add ПУТЬ'\'' или запусти '\''fraim init'\'' в проекте'
M_cli_proj_added='добавлено: {path}'
M_cli_proj_removed='убрано: {path}'

# doctor
M_cli_doc_source_git='источник:  {root} ({branch} {sha}, {date})'
M_cli_doc_source='источник:  {root}'
M_cli_doc_state='состояние: {path}'
M_cli_doc_latest='последняя известная версия'
M_cli_doc_procedures='Процедуры'
M_cli_doc_harnesses='Харнесы'
M_cli_doc_skills_ok='{n} скиллов, версия {ver}'
M_cli_doc_skills_mismatch='{n} скиллов, версии: {vers}(установлена {ver} — нужен fraim init)'
M_cli_doc_no_skills='найден, скиллы не установлены — запусти fraim init'
M_cli_doc_not_found='не найден'
M_cli_doc_registry='Реестр проектов'
M_cli_doc_registry_empty='пуст'
M_cli_doc_registry_count='проектов: {n}'
M_cli_doc_registry_gone='каталог пропал: {path}  ('\''fraim projects rm'\'' чтобы убрать)'

# show, build
M_cli_show_err_need_name='укажи имя процедуры: {list}'
M_cli_show_err_unknown='нет такой процедуры: {name}'
M_cli_build_plugin='плагин Claude Code: {n} скиллов'
M_cli_build_manifest='манифест: procedures/manifest.json'

# scaffold
M_cli_scaf_title='Скелет фундамента в {path}'
M_cli_scaf_err='не удалось развернуть скелет'
M_cli_scaf_registered='проект зарегистрирован в реестре'
M_cli_scaf_next='Дальше: {bootstrap} для нового проекта, {onboard} для существующего кода.'
M_cli_scaf_stub_note='Файлы помечены маркером fraim:stub — сторож считает их незаполненными, пока он на месте.'

# upgrade
M_cli_upg_err_empty='реестр проектов пуст — '\''fraim upgrade ПУТЬ'\'' для одного проекта или '\''fraim init'\'' в проекте'
M_cli_upg_skip_no_dir='каталога нет — пропущен; убрать из реестра: fraim projects rm {path}'
M_cli_upg_skip_unmanaged='не под системой — пропущен'
M_cli_upg_summary='Проектов: доведено {ok}, пропущено {skip}, с ошибкой {fail}'
M_cli_upg_err_unmanaged='здесь нечего обновлять: это не проект под системой. Завести — fraim scaffold'
M_cli_upg_title='Довожу фундамент до стандарта fraim {ver} в {path}'
M_cli_upg_err_scaffold='не удалось обновить фундамент'
M_cli_upg_err_sections='не удалось дописать разделы'
M_cli_upg_err_tasks='не удалось перевести задачи старого формата'
M_cli_upg_conf_refreshed='ai/fraim.conf — список настроек обновлён, удалённые ключи убраны'
M_cli_upg_done='готово — проверить: fraim status'

# version
M_cli_ver_source='источник: {root}'
M_cli_ver_git='ветка {branch} · коммит {sha} · {date}'
M_cli_ver_not_clone='источник: {root} (не git-клон)'

# publish
M_cli_pub_err_provider_arg='--provider требует имени'
M_cli_pub_err_url_arg='--url требует ссылки'
M_cli_pub_err_name_arg='--name требует имени'
M_cli_pub_err_flag='неизвестный флаг: {flag} (см. fraim help)'
M_cli_pub_err_extra='лишний аргумент: {arg} — имя задаётся через --name'
M_cli_pub_err_provider='неизвестный провайдер: {prov} (github, gitlab, url)'
M_cli_pub_err_no_git='git не установлен — отправлять нечем'
M_cli_pub_err_no_repo='здесь нет репозитория — заводится командой fraim scaffold'
M_cli_pub_nothing_to_clean='нечего вычищать: проверка ничего не нашла'
M_cli_pub_no_commits='нет ни одной точки сохранения — отправлять пока нечего'
M_cli_pub_save_and_retry='сохрани работу и повтори: fraim clean, либо fraim commit ВИД ТЕКСТ ПУТЬ...'
M_cli_pub_copy='Копия: {url}'
M_cli_pub_never_pushed='туда ни разу ничего не уезжало — настройку начали и не довели'
M_cli_pub_unpushed='не уехало точек: {n}'
M_cli_pub_all_pushed='по записям этой машины — всё уехало'
M_cli_pub_host_needs_net='что лежит на хосте на самом деле, сверяет fraim publish: для этого нужна сеть'
M_cli_pub_no_copy='Копии вне этой машины нет.'
M_cli_pub_risk_private='в приватную копию это отправляется с принятием риска (fraim publish --private),'
M_cli_pub_risk_public='в публичную — нет; вычистить вместо этого — fraim publish --brief'
M_cli_pub_asking_host='спрашиваю хост, что там лежит…'
M_cli_pub_synced='копия на месте и совпадает с этой машиной: {url}'
M_cli_pub_err_choice='не понял выбор'
M_cli_pub_err_no_target='не сказано, куда публиковать: --provider github|gitlab | --url ССЫЛКА'
M_cli_pub_err_no_url='без ссылки отправлять некуда'
M_cli_pub_err_url_needed='для --provider url нужна ссылка: --url ССЫЛКА'
M_cli_pub_repo_name='имя репозитория «{name}»: хосты принимают только латиницу, цифры, точку, дефис'
M_cli_pub_vis_src_yours='с твоих слов'
M_cli_pub_force_warn='--force: находки выше уедут на хост вместе с историей, и это необратимо'
M_cli_pub_ask_with_findings='Публикуем ВМЕСТЕ с находками в приватную копию? [y/N]'
M_cli_pub_ask='Публикуем? [y/N]'
M_cli_pub_plan_only='это был только план. Выполнить: fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='здесь нечего прибирать: это не проект под системой'
M_cli_clean_ask='Начать? [y/N]'
M_cli_clean_plan_only='это был только план. Выполнить: fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} больше нет: задача теперь карточка без плана — fraim tasks, task-new, task-seal (fraim help)'
M_cli_decide_usage='нужно: fraim decide "ЗАГОЛОВОК" [--supersedes "ЧТО ЗАМЕНЯЕТ"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes требует текста'
M_cli_inv_err_slug='нужен слаг расследования'
M_cli_commit_usage='нужно: fraim commit ВИД ТЕКСТ ПУТЬ... (пути обязательны — «всё» не бывает)'
M_cli_commit_err_kind='вид должен быть одним словом в нижнем регистре: task, deploy, onboard, archive…'
M_cli_commit_err_no_git='здесь нет git — точку сохранения поставить не во что'
M_cli_commit_failed='коммит не удался'

# dispatch
M_cli_disp_usage='нужно: fraim dispatch ПЛАН (или check / prepare / collect / verify / accept / list)'
M_cli_disp_usage_check='нужно: fraim dispatch check ПЛАН'
M_cli_disp_usage_verify='нужно: fraim dispatch verify СБОРКА ПОДЗАДАЧА [ВЕТКА]'
M_cli_disp_usage_collect='нужно: fraim dispatch collect СБОРКА [ПОДЗАДАЧА=ВЕТКА …]'
M_cli_disp_usage_accept='нужно: fraim dispatch accept СБОРКА'
M_cli_disp_err_plan_bad='план не годится для параллельной раздачи'
M_cli_disp_check_ok='план проходит dispatch-check'
M_cli_disp_err_no_build_plan='нет плана сборки {build}'
M_cli_disp_err_no_subtask='в сборке {build} нет подзадачи {sub}'
M_cli_disp_hint_collect='собрать круг:  fraim dispatch collect {build} [ПОДЗАДАЧА=ВЕТКА …]'
M_cli_disp_collected='круг собран в ветку {branch}'
M_cli_disp_accept_hint='fraim dispatch accept {build}  (сверка, мастер-проверка, чистка, отчёт)'
M_cli_disp_err_collect_partial='круг собран не полностью — разберись с отклонёнными и повтори'
M_cli_disp_err_accept='приёмка не прошла'
M_cli_disp_accepted='сборка {build} принята, проверена и в стволе'
M_cli_disp_not_accepted='сборка {build} проверена, в ствол не уведена — разберись и повтори'
M_cli_disp_err_no_plan='плана нет: {path}'
M_cli_disp_err_journal='не удалось завести журнал сборки'
M_cli_disp_build_title='Сборка {build} — кто что исполняет:'
M_cli_disp_plan_hint_verify='проверить один результат:  fraim dispatch verify {build} ПОДЗАДАЧА [ВЕТКА]'

# roles

# mode
M_cli_mode_gone='режимов больше нет: агент работает сам, в разговоре'
M_cli_mode_conductor_note='дирижёр и флот — процедура /conductor, её запускают по просьбе человека'
M_cli_mode_err_conf='не удалось убрать строку mode из ai/fraim.conf'
M_cli_mode_conf_done='строка mode убрана из ai/fraim.conf'
M_cli_mode_err_agents='не удалось обновить AGENTS.md'
M_cli_mode_agents_done='дирижёрский блок убран из AGENTS.md'
M_cli_mode_hook_done='хук SessionStart убран из .claude/settings.json'
M_cli_mode_hook_no_python='нет python3 — хук «{mark}» в .claude/settings.json убери руками'
M_cli_mode_hook_unreadable='.claude/settings.json не удалось прочитать — хук «{mark}» остался'
M_cli_mode_nothing='остатков старого режима здесь нет'
M_cli_disp_usage_prepare='нужно: fraim dispatch prepare СБОРКА'
M_cli_disp_retired='fraim dispatch {verb} больше нет: воркеров поднимают собственные субагенты харнеса (/conductor, шаг 4); чекауты для харнеса без изоляции — fraim dispatch prepare СБОРКА'
M_cli_retired_roles='fraim roles больше нет: воркеры работают на модели самого агента, если человек словами не назвал другую'
M_cli_disp_preparing='Чекауты сборки {build}:'
M_cli_disp_err_prepare='не все чекауты созданы — см. выше'
M_cli_disp_hint_spawn_prepared='по субагенту на чекаут: он работает там и читает свой бриф'
M_cli_disp_err_no_result='нет результата подзадачи {sub}: назовите её ветку или подготовьте чекаут'
M_cli_disp_err_write_brief='не удалось записать бриф подзадачи {id}'
M_cli_disp_brief_written='бриф {id} → {path}'
M_cli_disp_briefs_done='брифы записаны, журнал открыт: ai/builds/{build}/journal.md'
M_cli_disp_hint_spawn='поднимите по субагенту на бриф, каждого в своём worktree (изоляция вашего харнеса)'
M_cli_disp_hint_prepare='у харнеса нет изоляции:  fraim dispatch prepare {build}'
