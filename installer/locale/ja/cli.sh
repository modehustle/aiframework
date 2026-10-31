# The CLI itself (installer/bin/fraim): help, the commands' words, refusals.
M_cli_usage_head='fraim — エージェント駆動のプロジェクトのための運用レイヤー

あなたが入力するコマンド
  fraim                     fraim の画面 (ターミナル内)。fraim menu と同じ
  fraim menu                プロジェクト、ボード、バックログ、決定事項、設定、言語を 1 画面で
  fraim status [PATH]       プロジェクトで起きていること (機械向けは --json)
  fraim fleet [PATH]        作業の所在: プロジェクトのチェックアウトとフリートのランタイム
  fraim undo [HASH]         セーブポイントの一覧 / 元の状態に戻す
  fraim scaffold [PATH]     プロジェクトをシステムの管理下に置く
  fraim upgrade [PATH]      登録済みの全プロジェクトをこのバージョンの標準に合わせる
                            (PATH を指定するとそのプロジェクトのみ)
  fraim clean [--yes]       判断なしで直せるものをすべて片付ける
  fraim publish [--check]   このマシンの外にプロジェクトのコピー: 作成、プッシュ、照合
                            (--brief: 検出事項を除去するタスクをエージェント向けに出力)
  fraim dispatch PLAN       フリート: 計画を検査してビルドを開く
  fraim dispatch collect BUILD  ウェーブをビルドブランチにマージ
  fraim dispatch accept BUILD   指揮者による受け入れ: 照合、チェック、クリーンアップ、トランク
                            run BUILD: ランタイムでフリートを起動
                            watch BUILD: ワーカーについてランタイムが報告する内容
                            verify BUILD SUBTASK: ツリーをパスと照合
                            check PLAN · accept BUILD · list
  fraim mode                旧フリートモードの残骸をプロジェクトから削除
  fraim roles [set [NAME]]  ロール表: このマシンで各ロールが何に解決されるか
                            (set: エージェント、モデル、推論量を一覧から選ぶ)
  fraim init                スキルをインストール / 新しいハーネスを取り込む
  fraim update [--check]    新しいバージョンを取得して展開 (--check: 確認のみ、
                            --quiet: 自動起動用。何も出力せず、起動を妨げない)
  fraim doctor              何がどこにインストールされ、何がずれているか
  fraim config              有効な設定とその出所 (set / unset KEY)
  fraim projects            プロジェクトのレジストリ (add PATH / rm PATH)

エージェントと手順が呼ぶコマンド (覚える必要はありません)'
M_cli_usage_tail='
保守用
  fraim task-block, task-result, task-revise, plan-seal, reconcile-seal —
                            計画とともに削除されました。タスクは今はカードです
  fraim show NAME           手順のテキストを表示
  fraim build               リポジトリの成果物を再ビルド
  fraim version             バージョン
  fraim help                この画面

見張り番は決定的です: ファイル、git log、mtime だけを見ます。モデルもネットワークも
使わず、何も書き込みません。気づくのは見張り番、決めるのは人間です。'

# Shared words.
M_cli_err_unknown_command='不明なコマンド: {cmd}'
M_cli_err_unknown_flag='不明なフラグ: {flag}'
M_cli_err_subcommand='不明なサブコマンド: {sub}'
M_cli_err_no_dir='ディレクトリがありません: {path}'
M_cli_err_no_procedures='procedures/ ディレクトリが見つかりません'
M_cli_err_need_path='パスを指定してください'
M_cli_err_not_project='ここには ai/ がありません。システム管理下のプロジェクトではありません (fraim scaffold)'
M_cli_registered='プロジェクトを登録しました: {path}'
M_cli_context_block='コンテキストブロック → {path}'
M_cli_cancelled='キャンセルしました'

# init
M_cli_init_err_broken='procedures/ ディレクトリが見つかりません。インストールが壊れています'
M_cli_init_source='fraim {ver} · ソース: {root}'
M_cli_init_skills_built='ビルドしたスキル: {n} (手順 + マスタースキル)'
M_cli_init_harness_dir_failed='{label}: {dir} へのインストールに失敗しました'
M_cli_init_swept='以前の場所から削除しました: {path}'
M_cli_init_context_failed='{label}: {path} を更新できませんでした'
M_cli_init_no_harness='ハーネスが見つかりません'
M_cli_init_no_harness_copy='スキルは {path} にビルドされています。エージェントのディレクトリに手動でコピーするか、'
M_cli_init_no_harness_rerun='ハーネスをインストールして '\''fraim init'\'' を再実行してください (何度実行しても結果は同じです)。'
M_cli_init_registry_count='レジストリ内のプロジェクト: {n}。このバージョンに合わせるには: fraim upgrade'
M_cli_init_done='完了しました。確認: {cmd}'
M_cli_perm_added='~/.claude/settings.json に権限 Bash(fraim:*) を追加しました'
M_cli_perm_hint='Claude Code: ~/.claude/settings.json の permissions.allow に "Bash(fraim:*)" を追加してください'

# update
M_cli_upd_not_clone='ソースが git のクローンではないため、確認できません'
M_cli_upd_network_hint='ネットワークまたはリポジトリへのアクセスを確認してください: git ls-remote'
M_cli_upd_latest='最新バージョンがインストールされています ({ver})'
M_cli_upd_updated='fraim を更新しました: {from} → {to}'
M_cli_upd_err_flag='fraim update: 不明なオプション: {flag}'
M_cli_upd_title='fraim の更新'
M_cli_upd_was='更新前: {ver}'

# status
M_cli_status_unmanaged='{path} はシステム管理下にありません: ai/ も ARCHITECTURE.md もありません'
M_cli_status_unmanaged_hint='既存のプロジェクトを取り込むなら /onboard、新規なら /design-session → /bootstrap'

# fleet
M_cli_fleet_on_board_other='ボード上のタスク {n} 件'
M_cli_fleet_clean='クリーン'
M_cli_fleet_err_not_repo='{path} はリポジトリではないため、チェックアウトはなく、作ることもできません'

# projects
M_cli_proj_no_dir='(ディレクトリなし)'
M_cli_proj_empty='レジストリは空です。'\''fraim projects add PATH'\'' を実行するか、プロジェクト内で '\''fraim init'\'' を実行してください'
M_cli_proj_added='追加しました: {path}'
M_cli_proj_removed='削除しました: {path}'

# doctor
M_cli_doc_source_git='ソース: {root} ({branch} {sha}, {date})'
M_cli_doc_source='ソース: {root}'
M_cli_doc_state='状態:   {path}'
M_cli_doc_latest='既知の最新バージョン'
M_cli_doc_procedures='手順'
M_cli_doc_harnesses='ハーネス'
M_cli_doc_skills_ok='スキル {n} 個、バージョン {ver}'
M_cli_doc_skills_mismatch='スキル {n} 個、バージョン: {vers}(インストール済みは {ver}。fraim init が必要です)'
M_cli_doc_no_skills='見つかりましたが、スキルがインストールされていません。fraim init を実行してください'
M_cli_doc_not_found='見つかりません'
M_cli_doc_registry='プロジェクトのレジストリ'
M_cli_doc_registry_empty='空'
M_cli_doc_registry_count='プロジェクト: {n}'
M_cli_doc_registry_gone='ディレクトリがなくなっています: {path}  ('\''fraim projects rm'\'' で削除できます)'

# show, build
M_cli_show_err_need_name='手順の名前を指定してください: {list}'
M_cli_show_err_unknown='そのような手順はありません: {name}'
M_cli_build_plugin='Claude Code プラグイン: スキル {n} 個'
M_cli_build_manifest='マニフェスト: procedures/manifest.json'

# scaffold
M_cli_scaf_title='{path} に基盤の雛形を作成'
M_cli_scaf_err='雛形を作成できませんでした'
M_cli_scaf_registered='プロジェクトをレジストリに登録しました'
M_cli_scaf_next='次は、新規プロジェクトなら {bootstrap}、既存のコードなら {onboard} です。'
M_cli_scaf_stub_note='各ファイルには fraim:stub マーカーが付いています。マーカーがある間、見張り番はそのファイルを未記入として扱います。'

# upgrade
M_cli_upg_err_empty='プロジェクトのレジストリは空です。1 つのプロジェクトなら '\''fraim upgrade PATH'\''、またはプロジェクト内で '\''fraim init'\'' を実行してください'
M_cli_upg_skip_no_dir='ディレクトリがないためスキップしました。レジストリから削除するには: fraim projects rm {path}'
M_cli_upg_skip_unmanaged='システム管理下にないためスキップしました'
M_cli_upg_summary='プロジェクト: アップグレード {ok}、スキップ {skip}、失敗 {fail}'
M_cli_upg_err_unmanaged='ここにはアップグレードするものがありません: システム管理下のプロジェクトではありません。始めるには: fraim scaffold'
M_cli_upg_title='{path} の基盤を fraim {ver} の標準に合わせています'
M_cli_upg_err_scaffold='基盤をアップグレードできませんでした'
M_cli_upg_err_sections='セクションを追加できませんでした'
M_cli_upg_err_tasks='旧形式のタスクを変換できませんでした'
M_cli_upg_conf_refreshed='ai/fraim.conf: 設定の一覧を更新し、廃止されたキーを削除しました'
M_cli_upg_done='完了しました。確認: fraim status'

# version
M_cli_ver_source='ソース: {root}'
M_cli_ver_git='ブランチ {branch} · コミット {sha} · {date}'
M_cli_ver_not_clone='ソース: {root} (git のクローンではありません)'

# publish
M_cli_pub_err_provider_arg='--provider には名前が必要です'
M_cli_pub_err_url_arg='--url にはリンクが必要です'
M_cli_pub_err_name_arg='--name には名前が必要です'
M_cli_pub_err_flag='不明なフラグ: {flag} (fraim help を参照)'
M_cli_pub_err_extra='余分な引数: {arg}。名前は --name で指定します'
M_cli_pub_err_provider='不明なプロバイダー: {prov} (github, gitlab, url)'
M_cli_pub_err_no_git='git がインストールされていないため、プッシュできません'
M_cli_pub_err_no_repo='ここにはリポジトリがありません。fraim scaffold で作成できます'
M_cli_pub_nothing_to_clean='除去するものはありません: スキャンで何も見つかりませんでした'
M_cli_pub_no_commits='セーブポイントがまだ 1 つもないため、プッシュするものがありません'
M_cli_pub_save_and_retry='作業を保存してから再試行してください: fraim clean、または fraim commit KIND TEXT PATH...'
M_cli_pub_copy='コピー: {url}'
M_cli_pub_never_pushed='まだ一度もプッシュされていません。設定が途中で止まっています'
M_cli_pub_unpushed='未プッシュのセーブポイント: {n}'
M_cli_pub_all_pushed='このマシンの記録では、すべてプッシュ済みです'
M_cli_pub_host_needs_net='ホスト上の実際の状態は fraim publish が照合します。これにはネットワークが必要です'
M_cli_pub_no_copy='このマシンの外にコピーはありません。'
M_cli_pub_risk_private='非公開のコピーには、リスクを受け入れたうえで送れます (fraim publish --private)。'
M_cli_pub_risk_public='公開のコピーには送れません。代わりに除去するには: fraim publish --brief'
M_cli_pub_asking_host='ホストに内容を問い合わせています…'
M_cli_pub_synced='コピーは存在し、このマシンと一致しています: {url}'
M_cli_pub_err_choice='選択を認識できませんでした'
M_cli_pub_err_no_target='公開先が指定されていません: --provider github|gitlab | --url LINK'
M_cli_pub_err_no_url='リンクがないとプッシュ先がありません'
M_cli_pub_err_url_needed='--provider url にはリンクが必要です: --url LINK'
M_cli_pub_repo_name='リポジトリ名「{name}」: ホストが受け付けるのはラテン文字、数字、ドット、ハイフンだけです'
M_cli_pub_vis_src_yours='あなたの指定による'
M_cli_pub_force_warn='--force: 上記の検出事項は履歴とともにホストへ送られ、取り消せません'
M_cli_pub_ask_with_findings='検出事項を含めたまま、非公開のコピーに公開しますか? [y/N]'
M_cli_pub_ask='公開しますか? [y/N]'
M_cli_pub_plan_only='ここまでは計画のみです。実行するには: fraim publish --yes'

# clean
M_cli_clean_err_unmanaged='ここには片付けるものがありません: システム管理下のプロジェクトではありません'
M_cli_clean_ask='開始しますか? [y/N]'
M_cli_clean_plan_only='ここまでは計画のみです。実行するには: fraim clean --yes'

# the deterministic verbs
M_cli_retired_verb='fraim {verb} は廃止されました: タスクは計画のないカードになりました。fraim tasks、task-new、task-seal を使ってください (fraim help)'
M_cli_decide_usage='使い方: fraim decide "TITLE" [--supersedes "WHAT IT REPLACES"] <<'\''EOF'\'' … EOF'
M_cli_decide_err_sup='--supersedes にはテキストが必要です'
M_cli_inv_err_slug='調査のスラッグが必要です'
M_cli_commit_usage='使い方: fraim commit KIND TEXT PATH... (パスは必須です。「すべて」という指定はありません)'
M_cli_commit_err_kind='KIND は小文字の 1 単語にしてください: task, deploy, onboard, archive…'
M_cli_commit_err_no_git='ここには git がないため、セーブポイントを作れません'
M_cli_commit_failed='コミットに失敗しました'

# dispatch
M_cli_disp_usage='使い方: fraim dispatch PLAN (または check / prepare / collect / verify / accept / list)'
M_cli_disp_usage_check='使い方: fraim dispatch check PLAN'
M_cli_disp_usage_verify='使い方: fraim dispatch verify BUILD SUBTASK [BRANCH]'
M_cli_disp_usage_collect='使い方: fraim dispatch collect BUILD [SUBTASK=BRANCH …]'
M_cli_disp_usage_accept='使い方: fraim dispatch accept BUILD'
M_cli_disp_err_plan_bad='この計画は並列ディスパッチに適していません'
M_cli_disp_check_ok='計画は dispatch-check に合格しました'
M_cli_disp_err_no_build_plan='ビルド {build} の計画がありません'
M_cli_disp_err_no_subtask='ビルド {build} にサブタスク {sub} はありません'
M_cli_disp_hint_collect='ラウンドを集約:  fraim dispatch collect {build} [SUBTASK=BRANCH …]'
M_cli_disp_collected='ラウンドをブランチ {branch} に集約しました'
M_cli_disp_accept_hint='fraim dispatch accept {build}  (照合、マスターチェック、クリーンアップ、レポート)'
M_cli_disp_err_collect_partial='ラウンドの集約が完了していません。却下されたものに対処して再試行してください'
M_cli_disp_err_accept='受け入れに失敗しました'
M_cli_disp_accepted='ビルド {build} を受け入れ、チェックし、トランクに取り込みました'
M_cli_disp_not_accepted='ビルド {build} はチェック済みですが、トランクには取り込んでいません。問題を解決して再試行してください'
M_cli_disp_err_no_plan='計画がありません: {path}'
M_cli_disp_err_journal='ビルドのジャーナルを開けませんでした'
M_cli_disp_build_title='ビルド {build}: 誰が何を担当するか'
M_cli_disp_plan_hint_verify='1 つの結果を確認:  fraim dispatch verify {build} SUBTASK [BRANCH]'

# roles

# mode
M_cli_mode_gone='モードはもうありません: エージェントは会話の中で自分で作業します'
M_cli_mode_conductor_note='指揮者とフリートは /conductor 手順であり、人間が頼んだときに開始されます'
M_cli_mode_err_conf='ai/fraim.conf から mode の行を削除できませんでした'
M_cli_mode_conf_done='ai/fraim.conf から mode の行を削除しました'
M_cli_mode_err_agents='AGENTS.md を更新できませんでした'
M_cli_mode_agents_done='AGENTS.md から指揮者のブロックを削除しました'
M_cli_mode_hook_done='.claude/settings.json から SessionStart フックを削除しました'
M_cli_mode_hook_no_python='python3 がありません。.claude/settings.json から「{mark}」フックを手動で削除してください'
M_cli_mode_hook_unreadable='.claude/settings.json を読み取れませんでした。「{mark}」フックは残っています'
M_cli_mode_nothing='ここに旧モードの残骸はありません'
M_cli_disp_usage_prepare='使い方: fraim dispatch prepare BUILD'
M_cli_disp_retired='fraim dispatch {verb} は廃止されました: ワーカーはハーネス自身のサブエージェントが起動します (/conductor のステップ 4)。分離機能のないハーネス用のチェックアウトは fraim dispatch prepare BUILD'
M_cli_retired_roles='fraim roles は廃止されました: ワーカーはエージェント自身のモデルで動きます。人が言葉で別のモデルを指定した場合を除きます'
M_cli_disp_preparing='ビルド {build} のチェックアウト:'
M_cli_disp_err_prepare='すべてのチェックアウトは作成されませんでした。上を参照してください'
M_cli_disp_hint_spawn_prepared='チェックアウトごとにサブエージェントを 1 つ: そこで作業し、自分のブリーフを読みます'
M_cli_disp_err_no_result='サブタスク {sub} の結果がありません: ブランチを指定するか、チェックアウトを用意してください'
M_cli_disp_err_write_brief='サブタスク {id} のブリーフを書き込めませんでした'
M_cli_disp_brief_written='ブリーフ {id} → {path}'
M_cli_disp_briefs_done='ブリーフを書き込み、ジャーナルを開きました: ai/builds/{build}/journal.md'
M_cli_disp_hint_spawn='ブリーフごとにサブエージェントを起動し、それぞれ自分の worktree で動かします (ハーネスの分離機能)'
M_cli_disp_hint_prepare='ハーネスに分離機能がない場合:  fraim dispatch prepare {build}'
