-- IDE モード: `NVIM_IDE=1 nvim [path...]` 起動時に VSCode ライクなレイアウトを
-- 自動展開する。VSCode の `code` コマンド同様、引数なし / ディレクトリ / ファイル
-- いずれでも IDE レイアウトで起動する。
--   引数なし        … フルレイアウト(左上=codex)
--   ディレクトリ    … そのディレクトリへ cd してフルレイアウト(左上=codex)
--   ファイル        … ファイルを左上に開いた状態でレイアウト展開
--
-- レイアウトは「左ツリー / 右領域(上=codex・claude / 下=ターミナル)」。
-- codex(左上) と claude(右上) の2エージェントを agmsg 経由で会話・相互レビュー
-- させる運用を想定する。codex / claude / ターミナルは buflisted な端末バッファとして
-- 生成され、ファイルと同じく bufferline のタブに並ぶ。ペインにフォーカスして対応する
-- タブ(またはタブをクリック)を選ぶと、そのペインに端末/ファイルを呼び出せる。
-- env は起動直後に nil 化して子プロセス(ターミナル等)へ伝播させない。
--
-- 狭い画面でのフォールバック: iPad + Termius 等の狭い端末で 3 パネルを開くと、
-- ソフトウェアキーボード出現で上下がさらに圧縮され戻らなくなる。起動時の画面
-- サイズが NARROW_WIDTH / NARROW_HEIGHT 未満なら、対応する分割を作らずメインの
-- 1 ペインへフォールバックする(端末はタブとして待機し <leader>i で呼び出す)。
--   幅 < NARROW_WIDTH  … claude の左右分割と neo-tree を開かない
--   高さ < NARROW_HEIGHT … 下ターミナルの上下分割を開かない
-- 判定は起動時の 1 回のみ。起動後のリサイズでは組み替えない。

-- 各ペインで起動するコマンド(argv リスト)。.zshrc の PATH・fnm/node 初期化等を
-- 読ませるため、エージェントはインタラクティブ zsh 経由で起動する。
local CLAUDE_CMD = { "zsh", "-ic", "claude" }
local CODEX_CMD = { "zsh", "-ic", "codex" }
local SHELL_CMD = { vim.o.shell }

-- 狭い画面フォールバックのしきい値(起動時の画面サイズで判定)。
-- columns がこれ未満 → claude の左右分割と neo-tree を開かない。
-- lines がこれ未満   → 下ターミナルの上下分割を開かない。
-- iPad + Termius 横向きが概ね 100〜130 列なので 140 でカバーする。要調整なら変更。
local NARROW_WIDTH = 140
local NARROW_HEIGHT = 35

-- 端末バッファに付ける表示ラベルと役割の目印。bufferline の name_formatter が
-- term_label を、レイアウト/コマンドが term_role を参照する。
local TERMS = {
  codex = { label = "codex", cmd = CODEX_CMD },
  claude = { label = "claude", cmd = CLAUDE_CMD },
  terminal = { label = "terminal", cmd = SHELL_CMD },
}

-- 非フォーカスの端末ペインを「末尾にいるときだけ」追従スクロールさせる仕組み。
-- nvim の端末はフォーカス中かつ terminal-job モードのときしか末尾追従しないため、
-- IDE モードで codex/claude を並べると、片方をアクティブにするともう片方の出力が
-- 画面に流れてこない。これを補う。
--   follow[win]   = その窓が追従中か(nil=未登録は追従中とみなす)
--   ag_pending[b] = on_lines を 1 ティックにつき 1 回へ集約するフラグ
local follow = {}
local ag_pending = {}

-- 出力後、カレント窓を除く「buf を表示中で追従中」の窓を末尾へ寄せる。
-- 非カレントの端末窓は必ず terminal-normal モードなので、カーソルを最終行へ
-- 置けばビューが末尾を含むよう追従する。
local function follow_terminals(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local cur = vim.api.nvim_get_current_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= cur
      and vim.api.nvim_win_get_buf(w) == buf
      and follow[w] ~= false then
      pcall(vim.api.nvim_win_set_cursor, w, { count, 0 })
    end
  end
end

-- 端末バッファの出力を検知して追従処理をスケジュールする。on_lines は
-- fast-context で発火しカーソル API を直接呼べないため vim.schedule 経由にし、
-- 連続出力は ag_pending で 1 ティック 1 回へ集約する。make_term から呼ぶ。
local function attach_autoscroll(buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b)
      if ag_pending[b] then
        return false
      end
      ag_pending[b] = true
      vim.schedule(function()
        ag_pending[b] = nil
        follow_terminals(b)
      end)
      return false -- false=アタッチ維持(true で detach)
    end,
  })
end

-- ユーザーのスクロールだけで追従状態を更新する。出力で行が積まれても topline は
-- 動かず WinScrolled は発火しないので、ここで follow を false に倒すのは実スクロール
-- のみ。自前の自動スクロール後は w$==行数 になり再計算しても follow=true で整合する。
--   上に遡る → w$ < 行数 → follow=false(停止) / 最下部へ → w$ == 行数 → follow=true(再開)
vim.api.nvim_create_autocmd("WinScrolled", {
  group = vim.api.nvim_create_augroup("nvim_ide_autoscroll", { clear = true }),
  callback = function()
    if not vim.g.nvim_ide then
      return
    end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].buftype == "terminal" then
        follow[w] = vim.fn.line("w$", w) >= vim.api.nvim_buf_line_count(b)
      end
    end
  end,
})

-- 閉じた窓の追従状態を掃除(テーブルのリーク防止)。
vim.api.nvim_create_autocmd("WinClosed", {
  group = "nvim_ide_autoscroll",
  callback = function(ev)
    follow[tonumber(ev.match)] = nil
  end,
})

-- 名前付き・通常(buftype 空)の「実ファイル」バッファが残っているか
local function has_real_file_buffers()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b)
      and vim.bo[b].buflisted
      and vim.bo[b].buftype == ""
      and vim.api.nvim_buf_get_name(b) ~= "" then
      return true
    end
  end
  return false
end

local function buf_displayed(buf)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      return true
    end
  end
  return false
end

-- 実ファイルが 1 つも無くなったら、空無名バッファを表示している
-- メインエディタ窓にダッシュボードを出し、残った無名空バッファ([No Name] タブ)
-- を掃除する。フロート/ターミナル/neo-tree の窓は対象外。
local function dashboard_when_empty()
  if has_real_file_buffers() then
    return
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == ""
      and vim.bo[b].buftype == ""
      and vim.api.nvim_buf_get_name(b) == ""
      and vim.bo[b].filetype ~= "snacks_dashboard" then
      pcall(function() Snacks.dashboard.open({ win = w }) end)
      break
    end
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted
      and vim.bo[b].buftype == ""
      and vim.api.nvim_buf_get_name(b) == ""
      and not buf_displayed(b) then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

-- :q / :wq を賢く: バッファだけ閉じ、最後でも終了しない。
vim.api.nvim_create_user_command("SmartQ", function()
  pcall(function() Snacks.bufdelete() end)
end, { desc = "Close buffer (return to dashboard when it was the last)" })

vim.api.nvim_create_user_command("SmartWQ", function()
  pcall(vim.cmd.write)
  vim.cmd("SmartQ")
end, { desc = "Write then SmartQ" })

-- ファイルタブ(bufferline)を閉じていって最後の実ファイルが無くなったら、
-- [No Name] ではなくダッシュボードを表示する。閉じ方(×ボタン/:bd/
-- Snacks.bufdelete/SmartQ)を問わず効くよう BufDelete で捕捉する。
-- IDE モードのときだけ動作。
vim.api.nvim_create_autocmd("BufDelete", {
  group = vim.api.nvim_create_augroup("nvim_ide_dashboard", { clear = true }),
  callback = function(ev)
    if not vim.g.nvim_ide then
      return
    end
    -- 無名バッファの削除(上の掃除処理を含む)では反応しない = 再帰防止
    if ev.file == "" then
      return
    end
    vim.schedule(dashboard_when_empty)
  end,
})

-- 端末バッファを生成する(まだどの窓にも表示しない)。
-- buflisted=true なので bufferline にタブとして並ぶ。term_label / term_role を
-- 付け、レイアウトや name_formatter / IdeShow から識別できるようにする。
local function term_start(cmd)
  -- nvim 0.11 で termopen は非推奨。jobstart({term=true}) を優先する。
  if vim.fn.has("nvim-0.11") == 1 then
    vim.fn.jobstart(cmd, { term = true })
  else
    vim.fn.termopen(cmd)
  end
end

local function make_term(role)
  local spec = TERMS[role]
  local buf = vim.api.nvim_create_buf(true, false) -- listed=true, scratch=false
  vim.api.nvim_buf_call(buf, function()
    term_start(spec.cmd)
  end)
  vim.api.nvim_buf_set_var(buf, "term_label", spec.label)
  vim.api.nvim_buf_set_var(buf, "term_role", role)
  vim.bo[buf].buflisted = true
  attach_autoscroll(buf)
  return buf
end

-- 端末を表示する窓の見た目(行番号なし・折り返し)。グローバルは nowrap(コード編集
-- 向け)だが、端末は自身で幅に合わせて折り返すので横スクロールせず常に折り返す。
local function style_term_win(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = true
end

-- 端末ペインだった窓にファイル/通常バッファを表示するとき、行番号・サイン列・
-- 折り返しをグローバル既定(options.lua)へ戻す。
local function style_file_win(win)
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "yes"
  vim.wo[win].wrap = false
end

-- 指定 role の端末バッファを探す。
local function find_role_buf(role)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local ok, r = pcall(vim.api.nvim_buf_get_var, b, "term_role")
    if ok and r == role then
      return b
    end
  end
end

-- 指定 role の端末を表示している(フロートでない)窓を探す。
local function find_role_win(role)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      local b = vim.api.nvim_win_get_buf(w)
      local ok, r = pcall(vim.api.nvim_buf_get_var, b, "term_role")
      if ok and r == role then
        return w
      end
    end
  end
end

-- 現在表示中のファイルツリー(neo-tree)の占有幅。閉じていれば 0。
-- セパレータ 1 列を含めて返す。
local function neotree_width()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "neo-tree"
      and vim.api.nvim_win_get_config(w).relative == "" then
      return vim.api.nvim_win_get_width(w) + 1
    end
  end
  return 0
end

-- 上段(codex/エディタ)と claude ペインを左右 50/50 に保つ。
--   ツリーあり … (画面幅 - ツリー幅) を折半
--   ツリーなし … 画面幅を折半
-- claude ペインの幅だけ設定すれば、残りは左側が受け取る。
local function rebalance_panes()
  local cw = find_role_win("claude")
  if not cw then
    return
  end
  local avail = vim.o.columns - neotree_width()
  local target = math.max(20, math.floor(avail / 2))
  pcall(vim.api.nvim_win_set_width, cw, target)
end
vim.api.nvim_create_user_command("IdeRebalance", rebalance_panes,
  { desc = "Rebalance left(codex/editor) / claude panes to 50/50 (minus file tree)" })

-- 任意のバッファをフォーカス中(カレント)のペインへ表示する。これがファイル/端末を
-- ペインへ自由に入れ替える土台で、bufferline のタブクリック(ui.lua)からも呼ばれる。
-- tree や専用窓そのものを潰さないよう、フロートやツリー窓では何もしない。
-- 端末なら端末スタイル+挿入モード、それ以外(ファイル等)はファイルスタイルに戻す。
-- ui.lua から参照するためグローバルに公開する(hook_neotree_rebalance と同じ流儀)。
function _G.ide_place_buf_in_current(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
    return
  end
  vim.api.nvim_win_set_buf(win, buf)
  if vim.bo[buf].buftype == "terminal" then
    style_term_win(win)
    vim.cmd("startinsert")
  else
    style_file_win(win)
  end
end

-- カレント窓に指定 role の端末を呼び出す(=パネルを選んでタブを差し替える操作)。
local function show_role_in_current(role)
  local buf = find_role_buf(role)
  if not buf then
    vim.notify("IDE: '" .. role .. "' 端末が見つかりません", vim.log.levels.WARN)
    return
  end
  _G.ide_place_buf_in_current(buf)
end
vim.api.nvim_create_user_command("IdeShow", function(o)
  show_role_in_current(o.args)
end, {
  nargs = 1,
  complete = function() return { "codex", "claude", "terminal" } end,
  desc = "Show codex/claude/terminal in the focused pane",
})

-- opts.file=true でメインウィンドウに起動時のファイルを残す。false の場合は
-- メイン(左上)に codex 端末を表示する。
local function start_layout(opts)
  opts = opts or {}
  local main = vim.api.nvim_get_current_win()

  -- 狭い画面フォールバック判定(起動時サイズで 1 回だけ)。
  --   wide=false … claude の左右分割と neo-tree を開かない
  --   tall=false … 下ターミナルの上下分割を開かない
  local wide = vim.o.columns >= NARROW_WIDTH
  local tall = vim.o.lines >= NARROW_HEIGHT

  -- 端末バッファ(タブ)を先に生成。表示はこの後ペインへ割り当てる。
  -- 分割を省く場合もバッファは生成するので、すべて bufferline のタブとして残り
  -- <leader>ic / <leader>ia / <leader>it で任意のペインへ呼び出せる。
  local codex_buf = make_term("codex")
  local claude_buf = make_term("claude")
  local shell_buf = make_term("terminal")

  -- ① 下ターミナル(右領域の全幅・画面高の約28%)。この時点ではメインしか
  -- 無いので belowright split で画面全幅に作られ、後の ③ で左ツリーぶんだけ
  -- 右に寄って「右領域の全幅」になる。高さが狭ければ分割せずタブのみにする。
  if tall then
    if vim.api.nvim_win_is_valid(main) then
      vim.api.nvim_set_current_win(main)
    end
    vim.cmd("belowright split")
    local bottom = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(bottom, shell_buf)
    style_term_win(bottom)
    vim.cmd("resize " .. math.max(8, math.floor(vim.o.lines * 0.28)))
  end

  -- ② 上段を 左(codex/エディタ) / 右(claude) に分割。幅が狭ければ分割せず
  -- claude はタブのみにする。
  if wide then
    if vim.api.nvim_win_is_valid(main) then
      vim.api.nvim_set_current_win(main)
    end
    vim.cmd("rightbelow vsplit")
    local right = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(right, claude_buf)
    style_term_win(right)
  end

  -- 左上(main): ファイル引数があればそれを残し、無ければ codex を表示。
  if not opts.file then
    vim.api.nvim_win_set_buf(main, codex_buf)
    style_term_win(main)
  end

  -- ③ ファイルツリー(左・全高・cwd をルートに)。幅が狭ければ開かない。
  if wide then
    pcall(vim.cmd, "Neotree show left")
  end
  hook_neotree_rebalance()

  -- メインウィンドウへフォーカスを戻す(フロートにしない)
  if vim.api.nvim_win_is_valid(main) then
    vim.api.nvim_set_current_win(main)
  end

  -- ツリーを差し引いた左右 50/50 に初期サイズを合わせる(claude 窓があるときだけ)。
  if wide then
    vim.schedule(rebalance_panes)
  end
end

-- neo-tree の開閉(<leader>e トグル・:Neotree close・ツリー内 q 等いずれも)に
-- 追従して左右 50/50 を取り直す。neo-tree は遅延ロードなので、初回ロード後に
-- 一度だけイベント購読する。
local neotree_hooked = false
function hook_neotree_rebalance()
  if neotree_hooked then
    return
  end
  local ok, events = pcall(require, "neo-tree.events")
  if not ok then
    return
  end
  neotree_hooked = true
  for _, e in ipairs({ events.NEO_TREE_WINDOW_AFTER_OPEN, events.NEO_TREE_WINDOW_AFTER_CLOSE }) do
    events.subscribe({
      event = e,
      handler = function()
        if vim.g.nvim_ide then
          vim.schedule(rebalance_panes)
        end
      end,
    })
  end
  -- ツリーから端末ペイン(codex/claude/terminal)へファイルを開くと、その窓には
  -- 端末スタイル(行番号なし・折り返し)が残ってしまう。FILE_OPENED 発火時点では
  -- カレント窓 = ファイルを開いた窓なので、ファイル向けスタイルへ戻す。
  events.subscribe({
    event = events.FILE_OPENED,
    handler = function()
      if not vim.g.nvim_ide then
        return
      end
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_config(win).relative == ""
        and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
        style_file_win(win)
      end
    end,
  })
end

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("nvim_ide", { clear = true }),
  callback = function()
    if vim.env.NVIM_IDE ~= "1" then
      return
    end
    -- 子プロセスへ伝播させない
    vim.env.NVIM_IDE = nil
    vim.g.nvim_ide = true

    -- IDE モード中は :q / :wq を SmartQ / SmartWQ に自動展開
    vim.cmd([[cnoreabbrev <expr> q (getcmdtype()==':' && getcmdline()=='q') ? 'SmartQ' : 'q']])
    vim.cmd([[cnoreabbrev <expr> wq (getcmdtype()==':' && getcmdline()=='wq') ? 'SmartWQ' : 'wq']])

    -- パネル(カレント窓)へ端末を呼び出すキーマップ(<leader>i = ide グループ)。
    local map = function(lhs, role, desc)
      vim.keymap.set("n", lhs, function() show_role_in_current(role) end, { desc = desc })
    end
    map("<leader>ic", "codex", "Show codex in pane")
    map("<leader>ia", "claude", "Show claude in pane")
    map("<leader>it", "terminal", "Show terminal in pane")
    vim.keymap.set("n", "<leader>ir", rebalance_panes, { desc = "Rebalance panes 50/50" })

    local argc = vim.fn.argc()

    -- 引数なし: フルレイアウト(左上=codex)
    if argc == 0 then
      vim.schedule(function() start_layout({ file = false }) end)
      return
    end

    -- 単一ディレクトリ引数(`ide .` / `ide ~/project`): cd してフルレイアウト
    -- (左上=codex)。VSCode の `code <dir>` 相当。
    if argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
      local dir = vim.fn.fnamemodify(vim.fn.argv(0), ":p")
      vim.schedule(function()
        vim.cmd("cd " .. vim.fn.fnameescape(dir))
        -- ディレクトリ引数として開かれたバッファは bufferline にタブとして
        -- 残ってしまうため削除する。schedule 時点ではカレントが別バッファに
        -- 差し替わっていることがあるので、カレントに頼らず名前で走査する。
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(b) then
            local name = vim.api.nvim_buf_get_name(b)
            if name ~= "" and vim.fn.isdirectory(name) == 1 then
              pcall(vim.api.nvim_buf_delete, b, { force = true })
            end
          end
        end
        start_layout({ file = false })
      end)
      return
    end

    -- ファイル引数: 開いたファイルを左上(メイン)に残しレイアウト展開
    -- (VSCode の `code <file>` 相当)。codex はタブとして待機する。
    vim.schedule(function() start_layout({ file = true }) end)
  end,
})
