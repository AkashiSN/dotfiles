-- IDE モード: `NVIM_IDE=1 nvim [path...]` 起動時に VSCode ライクなレイアウトを
-- 自動展開する。VSCode の `code` コマンド同様、引数なし / ディレクトリ / ファイル
-- いずれでも IDE レイアウトで起動する。
--   引数なし        … フルレイアウト + ダッシュボード
--   ディレクトリ    … そのディレクトリへ cd してフルレイアウト + ダッシュボード
--   ファイル        … ファイルを開いた状態でレイアウト展開(ダッシュボードなし)
-- env は起動直後に nil 化して子プロセス(ターミナル等)へ伝播させない。

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

-- cmd を渡すとそのコマンドを起動するターミナルを開く(省略時は通常のシェル)。
local function open_terminal(split_cmd, size_cmd, cmd)
  vim.cmd(split_cmd)
  vim.cmd("terminal" .. (cmd and (" " .. cmd) or ""))
  if size_cmd then vim.cmd(size_cmd) end
  vim.bo.buflisted = false
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.opt_local.signcolumn = "no"
  -- グローバルは nowrap(コード編集向け)だが、ターミナル(claude/下部)は
  -- 自身で幅に合わせて折り返すので、横スクロールせず常に折り返す。
  vim.opt_local.wrap = true
end

-- 右の claude ペイン(start_layout で開いたターミナル)の窓を探す。
-- バッファに付けた目印 b:nvim_ide_claude で識別する。
local function find_claude_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      local b = vim.api.nvim_win_get_buf(w)
      local ok, marked = pcall(vim.api.nvim_buf_get_var, b, "nvim_ide_claude")
      if ok and marked then
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

-- メインエディタと右 claude ペインを左右 50/50 に保つ。
--   ツリーあり … (画面幅 - ツリー幅) を折半
--   ツリーなし … 画面幅を折半
-- claude ペインの幅だけ設定すれば、残りはメイン側が受け取る。
local function rebalance_panes()
  local cw = find_claude_win()
  if not cw then
    return
  end
  local avail = vim.o.columns - neotree_width()
  local target = math.max(20, math.floor(avail / 2))
  pcall(vim.api.nvim_win_set_width, cw, target)
end
vim.api.nvim_create_user_command("IdeRebalance", rebalance_panes,
  { desc = "Rebalance editor / claude panes to 50/50 (minus file tree)" })

-- neo-tree の開閉(<leader>e トグル・:Neotree close・ツリー内 q 等いずれも)に
-- 追従して左右 50/50 を取り直す。neo-tree は遅延ロードなので、初回ロード後に
-- 一度だけイベント購読する。
local neotree_hooked = false
local function hook_neotree_rebalance()
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
end

-- opts.dashboard=true でメインウィンドウにダッシュボードを表示する。
-- false の場合は現在のバッファ(起動時に開いたファイル等)をそのまま残す。
local function start_layout(opts)
  opts = opts or {}
  local main = vim.api.nvim_get_current_win()

  -- レイアウトは「左ツリー / 右領域(上=エディタ・claude / 下=ターミナル)」。
  -- 作成順が要: ①メインを上下に割り下を全幅ターミナルに ②上を左右に割り
  -- エディタ/claude に ③最後に左へ全高ツリー。この順なら下ターミナルは
  -- 「左ツリーを除く右領域の全幅」(エディタ+claude の真下)に渡る。

  -- ① 下ターミナル(右領域の全幅・画面高の約28%)。この時点ではメインしか
  -- 無いので belowright split で画面全幅に作られ、後の ③ で左ツリーぶんだけ
  -- 右に寄って「右領域の全幅」になる。
  open_terminal("belowright split", "resize " .. math.max(8, math.floor(vim.o.lines * 0.28)))

  -- ② 上段をエディタ(左) / claude(右)に分割。claude は .zshrc の
  -- PATH・fnm/node 初期化等を読ませるため一旦インタラクティブ zsh 経由で
  -- 起動する。幅は後段 rebalance_panes でツリーを差し引いた右領域内 50/50。
  if vim.api.nvim_win_is_valid(main) then
    vim.api.nvim_set_current_win(main)
  end
  open_terminal("rightbelow vsplit", nil, "zsh -ic claude")
  vim.b.nvim_ide_claude = true -- このバッファ = 右上の claude ペイン(目印)

  -- ③ ファイルツリー(左・全高・cwd をルートに)
  pcall(vim.cmd, "Neotree show left")
  hook_neotree_rebalance()

  -- メインウィンドウへフォーカスを戻す(フロートにしない)
  if vim.api.nvim_win_is_valid(main) then
    vim.api.nvim_set_current_win(main)
    if opts.dashboard then
      pcall(function() Snacks.dashboard.open({ win = main }) end)
    end
  end

  -- ツリーを差し引いた左右 50/50 に初期サイズを合わせる
  vim.schedule(rebalance_panes)
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

    local argc = vim.fn.argc()

    -- 引数なし: フルレイアウト + ダッシュボード
    if argc == 0 then
      vim.schedule(function() start_layout({ dashboard = true }) end)
      return
    end

    -- 単一ディレクトリ引数(`ide .` / `ide ~/project`): cd してフルレイアウト
    -- + ダッシュボード(VSCode の `code <dir>` 相当)
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
        start_layout({ dashboard = true })
      end)
      return
    end

    -- ファイル引数: 開いたファイルをメインに残しレイアウト展開
    -- (VSCode の `code <file>` 相当)
    vim.schedule(function() start_layout({ dashboard = false }) end)
  end,
})
