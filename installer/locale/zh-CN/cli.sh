# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim——面向智能体驱动项目的运维层

这些由你输入
  fraim                     fraim 界面（在终端中）——等同于 fraim menu
  fraim menu                项目、看板、待议清单、决策、设置和语言，一屏尽览
  fraim status [PATH]       项目当前的状况（--json 供机器读取）
  fraim fleet [PATH]        工作在哪里进行：项目的检出副本
  fraim undo [HASH]         列出保存点 / 恢复到原来的样子
  fraim scaffold [PATH]     把项目纳入系统管理
  fraim upgrade [PATH]      让每个已注册项目达到本版本的标准
                            （给出 PATH 则只处理这个项目）
  fraim clean [--yes]       整理所有无需判断就能修好的问题
  fraim publish [--check]   在本机之外建立项目副本：创建、推送、核对
                            （--brief——生成任务，让智能体清除扫描发现的内容）
  fraim dispatch PLAN       舰队：检查计划并开启一次构建
  fraim dispatch collect BUILD  把这一轮的结果合并进构建分支
  fraim dispatch accept BUILD   指挥的验收：核对、检查、清理、并入主干
                            prepare BUILD——为没有隔离的 harness 准备检出
                            verify BUILD SUBTASK [BRANCH]——对照路径检查一个结果
                            check PLAN · list
  fraim mode                清除项目中旧舰队模式的残留
  fraim init                安装技能 / 接入新的智能体工具
  fraim update [--check]    获取新版本并布置（--check——只检查；
                            --quiet——用于自动启动：静默，绝不妨碍启动）
  fraim doctor              什么装在哪里，哪些已经偏离
  fraim config              当前生效的设置及其来源（set / unset KEY）
  fraim projects            项目注册表（add PATH / rm PATH）

这些由智能体和流程调用——你不必记住'
M_cli_usage_tail='
辅助命令
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            已随计划一同移除：任务现在就是一张卡片
  fraim roles               已随角色表移除：工作者使用代理自己的模型
  fraim show NAME           打印某个流程的文本
  fraim build               重新构建仓库的产物
  fraim version             版本
  fraim help                本帮助

哨兵是确定性的：只看文件、git log 和 mtime。不用模型，不联网，也不写入任何东西。
它负责发现——由人来决定。'

# Shared words.
M_cli_err_unknown_command='未知命令：{cmd}'
M_cli_err_unknown_flag='未知选项：{flag}'
M_cli_err_subcommand='未知子命令：{sub}'
M_cli_err_no_dir='目录不存在：{path}'
M_cli_err_no_procedures='未找到 procedures/ 目录'
M_cli_err_need_path='请给出路径'
M_cli_err_not_project='这里没有 ai/——这不是纳入系统管理的项目（fraim scaffold）'
M_cli_registered='项目已注册：{path}'
M_cli_context_block='上下文区块 → {path}'
M_cli_cancelled='已取消'

# init
M_cli_init_err_broken='未找到 procedures/ 目录——安装已损坏'
M_cli_init_source='fraim {ver} · 源目录：{root}'
M_cli_init_skills_built='已构建技能：{n} 个（流程 + 主技能）'
M_cli_init_harness_dir_failed='{label}：安装到 {dir} 失败'
M_cli_init_swept='已从旧位置移除：{path}'
M_cli_init_context_failed='{label}：无法更新 {path}'
M_cli_init_no_harness='没有找到任何智能体工具'
M_cli_init_no_harness_copy='技能已构建在 {path}——请手动复制到你的智能体目录，'
M_cli_init_no_harness_rerun='或者安装一个智能体工具，然后再次运行 '\''fraim init'\''（这条命令可以重复执行）。'
M_cli_init_registry_count='注册表中的项目：{n} 个——让它们达到本版本的标准：fraim upgrade'
M_cli_init_done='完成。检查：{cmd}'
M_cli_perm_added='已将权限 Bash(fraim:*) 添加到 ~/.claude/settings.json'
M_cli_perm_hint='Claude Code：在 ~/.claude/settings.json 的 permissions.allow 中加入 "Bash(fraim:*)"'

# update
M_cli_upd_not_clone='源目录不是 git 克隆——无可检查'
M_cli_upd_network_hint='网络或仓库访问有问题：检查 git ls-remote'
M_cli_upd_latest='已安装最新版本（{ver}）'
M_cli_upd_updated='fraim 已更新：{from} → {to}'
M_cli_upd_err_flag='fraim update：未知选项：{flag}'
M_cli_upd_title='正在更新 fraim'
M_cli_upd_was='原版本：{ver}'

# status
M_cli_status_unmanaged='{path} 未纳入系统管理：既没有 ai/，也没有 ARCHITECTURE.md'
M_cli_status_unmanaged_hint='接入已有项目——/onboard；新项目——/design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_other='看板上有 {n} 个任务'
M_cli_fleet_clean='干净'
M_cli_fleet_err_not_repo='{path} 不是仓库——没有也不可能有检出副本'

# projects
M_cli_proj_no_dir='（目录不存在）'
M_cli_proj_empty='注册表为空——'\''fraim projects add PATH'\''，或在项目中运行 '\''fraim init'\'''
M_cli_proj_added='已添加：{path}'
M_cli_proj_removed='已移除：{path}'

# doctor
M_cli_doc_source_git='源目录：{root}（{branch} {sha}，{date}）'
M_cli_doc_source='源目录：{root}'
M_cli_doc_state='状态：  {path}'
M_cli_doc_latest='已知的最新版本'
M_cli_doc_procedures='流程'
M_cli_doc_harnesses='智能体工具'
M_cli_doc_skills_ok='{n} 个技能，版本 {ver}'
M_cli_doc_skills_mismatch='{n} 个技能，版本：{vers}（已安装 {ver}——需要运行 fraim init）'
M_cli_doc_no_skills='已找到，但未安装技能——运行 fraim init'
M_cli_doc_not_found='未找到'
M_cli_doc_registry='项目注册表'
M_cli_doc_registry_empty='空'
M_cli_doc_registry_count='项目：{n} 个'
M_cli_doc_registry_gone='目录已不存在：{path}  （用 '\''fraim projects rm'\'' 移除）'

# show, build
M_cli_show_err_need_name='请给出流程名：{list}'
M_cli_show_err_unknown='没有这个流程：{name}'
M_cli_build_plugin='Claude Code 插件：{n} 个技能'
M_cli_build_manifest='清单：procedures/manifest.json'

# scaffold
M_cli_scaf_title='{path} 中的基础文档骨架'
M_cli_scaf_err='无法布置骨架'
M_cli_scaf_registered='项目已登记到注册表'
M_cli_scaf_next='下一步：新项目用 {bootstrap}，已有代码用 {onboard}。'
M_cli_scaf_stub_note='这些文件带有 fraim:stub 标记——只要标记还在，哨兵就把它们算作未填写。'

# upgrade
M_cli_upg_err_empty='项目注册表为空——单个项目用 '\''fraim upgrade PATH'\''，或在项目中运行 '\''fraim init'\'''
M_cli_upg_skip_no_dir='目录不存在——已跳过；从注册表移除：fraim projects rm {path}'
M_cli_upg_skip_unmanaged='未纳入系统管理——已跳过'
M_cli_upg_summary='项目：已升级 {ok}，已跳过 {skip}，失败 {fail}'
M_cli_upg_err_unmanaged='这里没有可升级的：这不是纳入系统管理的项目。要新建，请用 fraim scaffold'
M_cli_upg_title='正在把 {path} 的基础文档升级到 fraim {ver} 的标准'
M_cli_upg_err_scaffold='无法升级基础文档'
M_cli_upg_err_sections='无法补充章节'
M_cli_upg_err_tasks='无法转换旧格式的任务'
M_cli_upg_conf_refreshed='ai/fraim.conf——设置列表已刷新，已删除的键已去掉'
M_cli_upg_done='完成——检查：fraim status'

# version
M_cli_ver_source='源目录：{root}'
M_cli_ver_git='分支 {branch} · 提交 {sha} · {date}'
M_cli_ver_not_clone='源目录：{root}（不是 git 克隆）'

# publish
M_cli_pub_err_provider_arg='--provider 需要一个名称'
M_cli_pub_err_url_arg='--url 需要一个链接'
M_cli_pub_err_name_arg='--name 需要一个名称'
M_cli_pub_err_flag='未知选项：{flag}（见 fraim help）'
M_cli_pub_err_extra='多余的参数：{arg}——名称要用 --name 指定'
M_cli_pub_err_provider='未知的提供方：{prov}（github、gitlab、url）'
M_cli_pub_err_no_git='未安装 git——没有工具可以用来推送'
M_cli_pub_err_no_repo='这里没有仓库——fraim scaffold 会创建一个'
M_cli_pub_nothing_to_clean='没有需要清除的：扫描什么也没发现'
M_cli_pub_no_commits='还没有任何保存点——没有可推送的'
M_cli_pub_save_and_retry='先保存工作再重试：fraim clean，或 fraim commit KIND TEXT PATH...'
M_cli_pub_copy='副本：{url}'
M_cli_pub_never_pushed='从未向那里推送过任何内容——配置开始了，但没有完成'
M_cli_pub_unpushed='未推送的保存点：{n}'
M_cli_pub_all_pushed='根据本机的记录——全部已推送'
M_cli_pub_host_needs_net='托管平台上实际有什么，由 fraim publish 核对：这需要联网'
M_cli_pub_no_copy='本机之外没有副本。'
M_cli_pub_risk_private='在接受风险的前提下，可以推送到私有副本（fraim publish --private），'
M_cli_pub_risk_public='公开副本则不行；要改为清除这些内容——fraim publish --brief'
M_cli_pub_asking_host='正在询问托管平台上有什么…'
M_cli_pub_synced='副本已就位，并与本机一致：{url}'
M_cli_pub_err_choice='没看懂这个选择'
M_cli_pub_err_no_target='没有说明发布到哪里：--provider github|gitlab | --url LINK'
M_cli_pub_err_no_url='没有链接就无处推送'
M_cli_pub_err_url_needed='--provider url 需要链接：--url LINK'
M_cli_pub_repo_name='仓库名“{name}”：托管平台只接受拉丁字母、数字、点和连字符'
M_cli_pub_vis_src_yours='依据你的说法'
M_cli_pub_force_warn='--force：上面的发现项会随历史一起推送到托管平台，而且无法撤回'
M_cli_pub_ask_with_findings='带着这些发现项发布到私有副本吗？[y/N]'
M_cli_pub_ask='发布吗？[y/N]'
M_cli_pub_plan_only='以上只是计划。要执行：fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='这里没有可清理的：这不是纳入系统管理的项目'
M_cli_clean_ask='开始吗？[y/N]'
M_cli_clean_plan_only='以上只是计划。要执行：fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} 已移除：任务现在是一张没有计划的卡片——fraim tasks、task-new、task-seal（fraim help）'
M_cli_decide_usage='用法：fraim decide "TITLE" [--supersedes "WHAT IT REPLACES"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes 需要文本'
M_cli_inv_err_slug='需要调查的 slug'
M_cli_commit_usage='用法：fraim commit KIND TEXT PATH...（路径必填——没有“全部”这一说）'
M_cli_commit_err_kind='类型必须是一个小写单词：task、deploy、onboard、archive…'
M_cli_commit_err_no_git='这里没有 git——保存点无处可放'
M_cli_commit_failed='提交失败'

# dispatch
M_cli_disp_usage='用法：fraim dispatch PLAN（或 check / prepare / collect / verify / accept / list）'
M_cli_disp_usage_check='用法：fraim dispatch check PLAN'
M_cli_disp_usage_verify='用法：fraim dispatch verify BUILD SUBTASK [BRANCH]'
M_cli_disp_usage_collect='用法：fraim dispatch collect BUILD [SUBTASK=BRANCH …]'
M_cli_disp_usage_accept='用法：fraim dispatch accept BUILD'
M_cli_disp_err_plan_bad='这个计划不适合并行分派'
M_cli_disp_check_ok='计划通过了 dispatch-check'
M_cli_disp_err_no_build_plan='没有构建 {build} 的计划'
M_cli_disp_err_no_subtask='构建 {build} 中没有子任务 {sub}'
M_cli_disp_hint_collect='收集这一轮：fraim dispatch collect {build} [SUBTASK=BRANCH …]'
M_cli_disp_collected='这一轮已收集到分支 {branch}'
M_cli_disp_accept_hint='fraim dispatch accept {build}  （核对、总检查、清理、报告）'
M_cli_disp_err_collect_partial='这一轮没有完全收集——处理被拒绝的部分后重试'
M_cli_disp_err_accept='验收失败'
M_cli_disp_accepted='构建 {build} 已验收、已检查，并已并入主干'
M_cli_disp_not_accepted='构建 {build} 已检查，但没有并入主干——处理后重试'
M_cli_disp_err_no_plan='没有计划：{path}'
M_cli_disp_err_journal='无法打开构建日志'
M_cli_disp_build_title='构建 {build}——分工如下：'
M_cli_disp_plan_hint_verify='检查一个结果：fraim dispatch verify {build} SUBTASK [BRANCH]'

# roles

# mode
M_cli_mode_gone='已经没有模式了：智能体在对话中自己工作'
M_cli_mode_conductor_note='指挥和舰队属于 /conductor 流程，在人提出要求时启动'
M_cli_mode_err_conf='无法从 ai/fraim.conf 中移除 mode 行'
M_cli_mode_conf_done='已从 ai/fraim.conf 中移除 mode 行'
M_cli_mode_err_agents='无法更新 AGENTS.md'
M_cli_mode_agents_done='已从 AGENTS.md 中移除指挥区块'
M_cli_mode_hook_done='已从 .claude/settings.json 中移除 SessionStart 钩子'
M_cli_mode_hook_no_python='没有 python3——请手动从 .claude/settings.json 中移除“{mark}”钩子'
M_cli_mode_hook_unreadable='无法读取 .claude/settings.json——“{mark}”钩子仍然存在'
M_cli_mode_nothing='这里没有旧模式的残留'
M_cli_disp_usage_prepare='用法：fraim dispatch prepare BUILD'
M_cli_disp_retired='fraim dispatch {verb} 已移除：工作者由你的 harness 自己的子代理启动（/conductor 第 4 步）；没有隔离的 harness 用检出——fraim dispatch prepare BUILD'
M_cli_retired_roles='fraim roles 已移除：工作者使用代理自己的模型，除非人用话语指定另一个'
M_cli_disp_preparing='构建 {build} 的检出：'
M_cli_disp_err_prepare='并非所有检出都已创建——见上文'
M_cli_disp_hint_spawn_prepared='每个检出一个子代理：它在那里工作并阅读自己的简报'
M_cli_disp_err_no_result='子任务 {sub} 没有结果：指明它的分支，或准备一个检出'
M_cli_disp_err_write_brief='无法写入子任务 {id} 的简报'
M_cli_disp_brief_written='简报 {id} → {path}'
M_cli_disp_briefs_done='简报已写好，日志已建立：ai/builds/{build}/journal.md'
M_cli_disp_hint_spawn='每份简报启动一个子代理，各自在自己的 worktree 中（你的 harness 的隔离）'
M_cli_disp_hint_prepare='你的 harness 没有隔离：fraim dispatch prepare {build}'
