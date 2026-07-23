-- yank 時にハイライト
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- 前回のカーソル位置を復元
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("last_loc", { clear = true }),
  callback = function(ev)
    local exclude = { "gitcommit" }
    local buf = ev.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) then
      return
    end
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Terraform / HCL のインデントは 2
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("indent_overrides", { clear = true }),
  pattern = { "terraform", "hcl", "lua", "yaml", "json", "javascript", "typescript", "typescriptreact" },
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
  end,
})

-- shpool 再アタッチ時の表示崩れ / マウス不作動を復旧する。手動でも :Resync で呼べる。
-- 原因: nvim は起動時に端末へ DEC private mode 2048(in-band resize)を問い合わせ、対応端末
-- (Ghostty)だと以後サイズを in-band 通知だけで追い、SIGWINCH では追従しなくなる。shpool は
-- 再アタッチ時に pty のサイズを更新するが in-band 通知は生成しないので、nvim は古いサイズのまま
-- 描画し続ける。マウス有効化シーケンスも新しい端末には送られていないので効かない。
-- 対策:
--   * mode 2048 を再アーム(\027[?2048h)。対応端末はこれで現在サイズを in-band で返すため nvim が追従し、
--     以後のウィンドウリサイズも再び in-band で届く。
--   * それでもサイズが食い違っていれば、pty の実サイズを ioctl で読んで 'lines' / 'columns' へ直接
--     反映する。端末の応答に依存しないので in-band 非対応の端末(iOS の Termius VT100 など)から
--     再アタッチしても追従する。shpool はアタッチ直後に中間サイズを挟むことがあるので数回読み直す。
--   * マウス有効化シーケンスを再送する。off と on を別々の defer_fn(=別タイマー)に分け、それぞれの
--     コールバック終了時にフラッシュさせるのが要点。同一コールバック内の off→on や defer_fn+
--     vim.schedule では nvim が差し引き無変化とみなし DECRST/DECSET を一切出さず、再送にならない
--     (タイマー起点=cmdline のようなフラッシュ境界が入らないため)。resize が落ち着いてから撃つよう
--     少し遅らせる。
-- 手動専用のコマンド。リサイズ後の表示崩れ / マウス不作動が起きたら :Resync で復旧する。

-- nvim を動かしている pty の実サイズ。nvim 自身の fd 0 には触れず /proc/self/fd/0 を開き直して読む
-- (uv の tty ハンドルを閉じると開いた fd も閉じるため、fd 0 を直接渡すと nvim の入力が壊れる)。
-- /proc が無い環境や stdin が tty でない環境では nil を返し、呼び出し側は何もしない。
local function pty_winsize()
  local ok, fd = pcall(vim.uv.fs_open, "/proc/self/fd/0", "r", 438)
  if not ok or not fd then
    return
  end
  local w, h
  local got = pcall(function()
    local tty = vim.uv.new_tty(fd, true)
    w, h = tty:get_winsize()
    tty:close()
  end)
  if not got then
    pcall(vim.uv.fs_close, fd)
    return
  end
  if w and h and w > 0 and h > 0 then
    return w, h
  end
end

-- pty の実サイズを nvim へ反映する。既に一致していれば何も書かない。'lines'/'columns' を設定すると
-- nvim は端末へリサイズ要求(CSI 8;h;w t)を送るので、in-band で追従済みの端末には触らせない。
local function apply_pty_size()
  local w, h = pty_winsize()
  if not w then
    return
  end
  if h ~= vim.o.lines then
    vim.o.lines = h
  end
  if w ~= vim.o.columns then
    vim.o.columns = w
  end
end

local function resync()
  io.stdout:write("\027[?2048h")
  io.stdout:flush()                                    -- 端末へ即送る(応答を待つので stdio に溜めない)
  -- 2048 対応端末の in-band 応答を待ってから、まだ食い違っていれば pty の実サイズを当てる
  vim.defer_fn(apply_pty_size, 250)
  vim.defer_fn(apply_pty_size, 600)
  vim.defer_fn(apply_pty_size, 1000)
  local m = vim.o.mouse
  vim.defer_fn(function()
    vim.o.mouse = ""                                   -- 無効化(このコールバック終了時にフラッシュ → DECRST 送出)
    vim.defer_fn(function() vim.o.mouse = m end, 30)   -- 別タイマーで有効化 → DECSET 送出
  end, 80)
end
vim.api.nvim_create_user_command("Resync", resync, {})

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

-- 実ファイルが 1 つも無くなったら、空無名バッファを表示しているメインエディタ窓に
-- ダッシュボードを出し、残った無名空バッファ([No Name] タブ)を掃除する。
-- フロート/ターミナル/neo-tree の窓は対象外。
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

-- ファイルタブ(bufferline)を閉じていって最後の実ファイルが無くなったら、
-- [No Name] ではなくダッシュボードを表示する。閉じ方(×ボタン/:bd/
-- Snacks.bufdelete/<leader>bd)を問わず効くよう BufDelete で捕捉する。
vim.api.nvim_create_autocmd("BufDelete", {
  group = vim.api.nvim_create_augroup("dashboard_when_empty", { clear = true }),
  callback = function(ev)
    -- 無名バッファの削除(上の掃除処理を含む)では反応しない = 再帰防止
    if ev.file == "" then
      return
    end
    vim.schedule(dashboard_when_empty)
  end,
})
