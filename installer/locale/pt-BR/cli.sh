# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim — a camada operacional para projetos conduzidos por agentes

Estes você digita
  fraim                     a tela do fraim (no terminal) — o mesmo que fraim menu
  fraim menu                projeto, quadro, backlog, decisões, configurações e idioma numa só tela
  fraim status [PATH]       o que está acontecendo no projeto (--json para máquinas)
  fraim fleet [PATH]        onde o trabalho está: checkouts do projeto e o ambiente da frota
  fraim undo [HASH]         listar os pontos de salvamento / deixar tudo como estava
  fraim scaffold [PATH]     colocar um projeto sob o sistema
  fraim upgrade [PATH]      colocar todos os projetos do registro no padrão desta versão
                            (PATH — só este projeto)
  fraim clean [--yes]       arrumar tudo o que se resolve sem julgamento
  fraim publish [--check]   uma cópia do projeto fora desta máquina: criar, enviar, conferir
                            (--brief — uma tarefa para o agente limpar o que foi achado)
  fraim dispatch PLAN       frota: verificar o plano e abrir um build
  fraim dispatch collect BUILD  fazer merge de uma onda no branch do build
  fraim dispatch accept BUILD   o aceite do maestro: conferir, verificar, limpar, tronco
                            run BUILD — iniciar a frota no ambiente de execução
                            watch BUILD — o que o ambiente diz sobre os workers
                            verify BUILD SUBTASK — conferir a árvore com os caminhos
                            check PLAN · accept BUILD · list
  fraim mode                remover do projeto as sobras do antigo modo frota
  fraim roles [set [NAME]]  a tabela de papéis: no que cada papel se resolve nesta máquina
                            (set — escolher agente, modelo e esforço de uma lista)
  fraim init                instalar as skills / reconhecer um novo harness
  fraim update [--check]    buscar a nova versão e distribuí-la (--check — só verificar;
                            --quiet — para o início automático: silencioso, nunca atrapalha)
  fraim doctor              o que está instalado onde, o que divergiu
  fraim config              o que está em vigor e de onde vem (set / unset KEY)
  fraim projects            o registro de projetos (add PATH / rm PATH)

Estes são chamados por agentes e procedimentos — você não precisa decorá-los'
M_cli_usage_tail='
Serviço
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            removidos junto com os planos: uma tarefa agora é um cartão
  fraim show NAME           exibir o texto de um procedimento
  fraim build               recompilar os artefatos do repositório
  fraim version             a versão
  fraim help                esta tela

O vigia é determinístico: arquivos, git log e mtime. Sem modelo, sem rede, e ele
não escreve nada. Ele aponta — quem decide é o humano.'

# Shared words.
M_cli_err_unknown_command='comando desconhecido: {cmd}'
M_cli_err_unknown_flag='flag desconhecida: {flag}'
M_cli_err_subcommand='subcomando desconhecido: {sub}'
M_cli_err_no_dir='diretório inexistente: {path}'
M_cli_err_no_procedures='diretório procedures/ não encontrado'
M_cli_err_need_path='informe um caminho'
M_cli_err_not_project='não há ai/ aqui — este não é um projeto sob o sistema (fraim scaffold)'
M_cli_registered='projeto registrado: {path}'
M_cli_context_block='bloco de contexto → {path}'
M_cli_cancelled='cancelado'

# init
M_cli_init_err_broken='diretório procedures/ não encontrado — a instalação está danificada'
M_cli_init_source='fraim {ver} · origem: {root}'
M_cli_init_skills_built='skills geradas: {n} (procedimentos + skill mestre)'
M_cli_init_harness_failed='{label}: a instalação falhou'
M_cli_init_context_failed='{label}: não foi possível atualizar {path}'
M_cli_init_no_harness='nenhum harness encontrado'
M_cli_init_no_harness_copy='as skills foram geradas em {path} — copie-as à mão para o diretório do seu agente,'
M_cli_init_no_harness_rerun='ou instale um harness e rode '\''fraim init'\'' de novo (o comando é idempotente).'
M_cli_init_registry_count='projetos no registro: {n} — para colocá-los nesta versão: fraim upgrade'
M_cli_init_done='Pronto. Confira: {cmd}'
M_cli_perm_added='permissão Bash(fraim:*) adicionada a ~/.claude/settings.json'
M_cli_perm_hint='Claude Code: adicione "Bash(fraim:*)" a permissions.allow em ~/.claude/settings.json'

# update
M_cli_upd_not_clone='a origem não é um clone git — nada a verificar'
M_cli_upd_network_hint='rede ou acesso ao repositório: confira com git ls-remote'
M_cli_upd_latest='a versão mais recente já está instalada ({ver})'
M_cli_upd_updated='fraim atualizado: {from} → {to}'
M_cli_upd_err_flag='fraim update: opção desconhecida: {flag}'
M_cli_upd_title='Atualizando o fraim'
M_cli_upd_was='antes: {ver}'

# status
M_cli_status_unmanaged='{path} não está sob o sistema: não há ai/ nem ARCHITECTURE.md'
M_cli_status_unmanaged_hint='para trazer um projeto existente — /onboard; um novo — /design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_one='{n} tarefa no quadro'
M_cli_fleet_on_board_other='{n} tarefas no quadro'
M_cli_fleet_clean='limpo'
M_cli_fleet_err_not_repo='{path} não é um repositório — não há checkouts, nem pode haver'
M_cli_fleet_ade_alive='{label} ({cmd}) — o ambiente responde'
M_cli_fleet_ade_silent='{label} ({cmd}) — instalado, o ambiente não responde'
M_cli_fleet_auto_free='{label}: um agente agendado trabalha neste projeto — garanta que ele não edite o código pelas suas costas'
M_cli_fleet_auto_watchman='{label}: o vigia roda de forma agendada — isso é observação, não edição'
M_cli_fleet_no_ade='nenhum ambiente de frota encontrado nesta máquina'

# projects
M_cli_proj_no_dir='(sem diretório)'
M_cli_proj_empty='o registro está vazio — '\''fraim projects add PATH'\'' ou rode '\''fraim init'\'' dentro de um projeto'
M_cli_proj_added='adicionado: {path}'
M_cli_proj_removed='removido: {path}'

# doctor
M_cli_doc_source_git='origem: {root} ({branch} {sha}, {date})'
M_cli_doc_source='origem: {root}'
M_cli_doc_state='estado: {path}'
M_cli_doc_latest='versão mais recente conhecida'
M_cli_doc_procedures='Procedimentos'
M_cli_doc_harnesses='Harnesses'
M_cli_doc_skills_ok='{n} skills, versão {ver}'
M_cli_doc_skills_mismatch='{n} skills, versões: {vers}(instalada {ver} — é preciso rodar fraim init)'
M_cli_doc_no_skills='encontrado, skills não instaladas — rode fraim init'
M_cli_doc_not_found='não encontrado'
M_cli_doc_registry='Registro de projetos'
M_cli_doc_registry_empty='vazio'
M_cli_doc_registry_count='projetos: {n}'
M_cli_doc_registry_gone='o diretório sumiu: {path}  ('\''fraim projects rm'\'' para removê-lo)'

# show, build
M_cli_show_err_need_name='informe o nome de um procedimento: {list}'
M_cli_show_err_unknown='procedimento inexistente: {name}'
M_cli_build_plugin='plugin do Claude Code: {n} skills'
M_cli_build_manifest='manifesto: procedures/manifest.json'

# scaffold
M_cli_scaf_title='Esqueleto da fundação em {path}'
M_cli_scaf_err='não foi possível montar o esqueleto'
M_cli_scaf_registered='projeto adicionado ao registro'
M_cli_scaf_next='Próximo passo: {bootstrap} para um projeto novo, {onboard} para código existente.'
M_cli_scaf_stub_note='Os arquivos levam o marcador fraim:stub — enquanto ele estiver lá, o vigia os conta como não preenchidos.'

# upgrade
M_cli_upg_err_empty='o registro de projetos está vazio — '\''fraim upgrade PATH'\'' para um projeto ou '\''fraim init'\'' dentro de um projeto'
M_cli_upg_skip_no_dir='sem diretório — pulado; remova-o do registro: fraim projects rm {path}'
M_cli_upg_skip_unmanaged='não está sob o sistema — pulado'
M_cli_upg_summary='Projetos: com upgrade {ok}, pulados {skip}, com falha {fail}'
M_cli_upg_err_unmanaged='nada para fazer upgrade aqui: este não é um projeto sob o sistema. Para começar um — fraim scaffold'
M_cli_upg_title='Colocando a fundação no padrão do fraim {ver} em {path}'
M_cli_upg_err_scaffold='não foi possível fazer o upgrade da fundação'
M_cli_upg_err_sections='não foi possível adicionar as seções'
M_cli_upg_err_tasks='não foi possível converter as tarefas do formato antigo'
M_cli_upg_conf_refreshed='ai/fraim.conf — lista de configurações atualizada, chaves removidas descartadas'
M_cli_upg_done='pronto — confira: fraim status'

# version
M_cli_ver_source='origem: {root}'
M_cli_ver_git='branch {branch} · commit {sha} · {date}'
M_cli_ver_not_clone='origem: {root} (não é um clone git)'

# publish
M_cli_pub_err_provider_arg='--provider exige um nome'
M_cli_pub_err_url_arg='--url exige um link'
M_cli_pub_err_name_arg='--name exige um nome'
M_cli_pub_err_flag='flag desconhecida: {flag} (veja fraim help)'
M_cli_pub_err_extra='argumento a mais: {arg} — o nome é dado com --name'
M_cli_pub_err_provider='provedor desconhecido: {prov} (github, gitlab, url)'
M_cli_pub_err_no_git='o git não está instalado — não há com o que fazer push'
M_cli_pub_err_no_repo='não há repositório aqui — fraim scaffold cria um'
M_cli_pub_nothing_to_clean='nada para limpar: a varredura não achou nada'
M_cli_pub_no_commits='ainda não há nenhum ponto de salvamento — nada para enviar'
M_cli_pub_save_and_retry='salve o trabalho e tente de novo: fraim clean, ou fraim commit KIND TEXT PATH...'
M_cli_pub_copy='Cópia: {url}'
M_cli_pub_never_pushed='nada foi enviado para lá ainda — a configuração começou e não terminou'
M_cli_pub_unpushed='pontos de salvamento não enviados: {n}'
M_cli_pub_all_pushed='pelos registros desta máquina — tudo foi enviado'
M_cli_pub_host_needs_net='o que realmente está no host é conferido por fraim publish: isso exige rede'
M_cli_pub_no_copy='Não há cópia fora desta máquina.'
M_cli_pub_risk_private='para uma cópia privada isto vai com o risco aceito (fraim publish --private),'
M_cli_pub_risk_public='para uma pública — não; para limpar em vez disso — fraim publish --brief'
M_cli_pub_asking_host='perguntando ao host o que há lá…'
M_cli_pub_synced='a cópia está no lugar e bate com esta máquina: {url}'
M_cli_pub_err_choice='não entendi a escolha'
M_cli_pub_err_no_target='não foi dito onde publicar: --provider github|gitlab | --url LINK'
M_cli_pub_err_no_url='sem um link não há para onde enviar'
M_cli_pub_err_url_needed='--provider url exige um link: --url LINK'
M_cli_pub_repo_name='nome do repositório «{name}»: os hosts só aceitam letras latinas, dígitos, ponto e hífen'
M_cli_pub_vis_src_yours='pela sua palavra'
M_cli_pub_force_warn='--force: os achados acima vão para o host junto com o histórico, e isso não tem volta'
M_cli_pub_ask_with_findings='Publicar COM os achados na cópia privada? [s/N]'
M_cli_pub_ask='Publicar? [s/N]'
M_cli_pub_plan_only='isso foi só o plano. Para executá-lo: fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='nada para limpar aqui: este não é um projeto sob o sistema'
M_cli_clean_ask='Começar? [s/N]'
M_cli_clean_plan_only='isso foi só o plano. Para executá-lo: fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} não existe mais: uma tarefa agora é um cartão sem plano — fraim tasks, task-new, task-seal (fraim help)'
M_cli_decide_usage='uso: fraim decide "TITLE" [--supersedes "WHAT IT REPLACES"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes exige um texto'
M_cli_inv_err_slug='informe o slug da investigação'
M_cli_commit_usage='uso: fraim commit KIND TEXT PATH... (os caminhos são obrigatórios — não existe «tudo»)'
M_cli_commit_err_kind='o tipo deve ser uma palavra em minúsculas: task, deploy, onboard, archive…'
M_cli_commit_err_no_git='não há git aqui — não há onde criar um ponto de salvamento'
M_cli_commit_failed='o commit falhou'

# dispatch
M_cli_disp_usage='uso: fraim dispatch PLAN (ou check / run / watch / collect / verify / accept / list)'
M_cli_disp_usage_check='uso: fraim dispatch check PLAN'
M_cli_disp_usage_verify='uso: fraim dispatch verify BUILD SUBTASK [BASE]'
M_cli_disp_usage_run='uso: fraim dispatch run BUILD [WAVE]'
M_cli_disp_usage_watch='uso: fraim dispatch watch BUILD'
M_cli_disp_usage_collect='uso: fraim dispatch collect BUILD [WAVE]'
M_cli_disp_usage_accept='uso: fraim dispatch accept BUILD'
M_cli_disp_err_plan_bad='o plano não serve para o dispatch paralelo'
M_cli_disp_check_ok='o plano passa no dispatch-check'
M_cli_disp_err_no_build_plan='não há plano para o build {build}'
M_cli_disp_err_no_subtask='o build {build} não tem a subtarefa {sub}'
M_cli_disp_checkout='checkout da subtarefa: {path}'
M_cli_disp_no_checkout='não há checkout separado {name} — verificando a raiz do projeto'
M_cli_disp_launching='Iniciando a frota do build {build}...'
M_cli_disp_launched='a frota está no ar'
M_cli_disp_hint_watch='estado:          fraim dispatch watch {build}'
M_cli_disp_hint_collect='coletar onda:    fraim dispatch collect {build}'
M_cli_disp_launch_partial='alguns workers não iniciaram — o que iniciou está registrado em ai/builds/{build}/fleet.tsv'
M_cli_disp_watch_not_up='não iniciou'
M_cli_disp_watch_unexpected='o ambiente respondeu de forma inesperada:'
M_cli_disp_watch_note_terminal='o estado do terminal não é o status da tarefa: uma tarefa concluída pode'
M_cli_disp_watch_note_verify='manter o terminal ativo. O que está feito — o dispatch verify mostra.'
M_cli_disp_collected='a onda foi coletada no branch {branch}'
M_cli_disp_next_wave='próxima onda:  fraim dispatch run {build}'
M_cli_disp_next_wave_note='(onda {wave} — os workers vão partir do branch coletado)'
M_cli_disp_all_collected='todas as ondas foram coletadas — aceite o trabalho da frota:'
M_cli_disp_accept_hint='fraim dispatch accept {build}  (conferência, verificação mestre, limpeza, relatório)'
M_cli_disp_err_collect_partial='a onda não foi toda coletada — resolva as rejeitadas e tente de novo'
M_cli_disp_err_accept='o aceite falhou'
M_cli_disp_accepted='build {build} aceito, verificado e no tronco'
M_cli_disp_not_accepted='build {build} verificado, não levado ao tronco — resolva e tente de novo'
M_cli_disp_err_no_plan='plano inexistente: {path}'
M_cli_disp_err_journal='não foi possível abrir o diário do build'
M_cli_disp_build_title='Build {build} — quem faz o quê:'
M_cli_disp_err_write_task='não foi possível gravar a tarefa da subtarefa {id}'
M_cli_disp_task_written='tarefa {id} → {path}'
M_cli_disp_tasks_done='tarefas gravadas, diário aberto: ai/builds/{build}/journal.md'
M_cli_disp_plan_hint_run='iniciar onda:    fraim dispatch run {build}'
M_cli_disp_plan_no_ade='não há ambiente de execução nesta máquina — as tarefas podem ser feitas à mão'
M_cli_disp_plan_hint_collect='coletar onda:      fraim dispatch collect {build}'
M_cli_disp_plan_hint_verify='conferir a árvore: fraim dispatch verify {build} SUBTASK'

# roles
M_cli_roles_err_form='«{value}» não está no formato agent:model:effort'
M_cli_roles_err_write='não foi possível gravar em {path}'
M_cli_roles_err_no_tty='a escolha precisa de um terminal — ou defina direto: fraim roles set KEY agent:model:effort'
M_cli_roles_pick_key='O que vamos definir — uma classe de modelo ou um procedimento?'
M_cli_roles_pick_agent='Agente:'
M_cli_roles_pick_model='Modelo:'
M_cli_roles_pick_effort='Esforço:'
M_cli_roles_err_result='resultou em «{value}» — isso não é agent:model:effort'
M_cli_roles_pick_level='Onde gravar?'
M_cli_roles_level_machine='nesta máquina (~/.fraim/config)'
M_cli_roles_level_project='só neste projeto (ai/fraim.conf)'
M_cli_roles_none='nenhum papel definido — tudo vai para o padrão embutido:'
M_cli_roles_set_hint='para definir um: fraim config set role_refactor claude:haiku:medium'
M_cli_roles_col_role='papel'
M_cli_roles_col_agent='agente'
M_cli_roles_col_model='modelo'
M_cli_roles_col_effort='esforço'
M_cli_roles_col_source='origem'

# mode
M_cli_mode_gone='não existem mais modos: o agente trabalha sozinho, na conversa'
M_cli_mode_conductor_note='o maestro e a frota são o procedimento /conductor, iniciado quando o humano pede'
M_cli_mode_err_conf='não foi possível remover a linha de modo de ai/fraim.conf'
M_cli_mode_conf_done='a linha de modo foi removida de ai/fraim.conf'
M_cli_mode_err_agents='não foi possível atualizar AGENTS.md'
M_cli_mode_agents_done='o bloco do maestro foi removido de AGENTS.md'
M_cli_mode_hook_done='o hook SessionStart foi removido de .claude/settings.json'
M_cli_mode_hook_no_python='não há python3 — remova o hook «{mark}» de .claude/settings.json à mão'
M_cli_mode_hook_unreadable='não foi possível ler .claude/settings.json — o hook «{mark}» continua lá'
M_cli_mode_nothing='não há sobras do modo antigo aqui'
