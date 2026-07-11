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
-- 自動起動(reattach 検知)は ide.lua が Signal SIGUSR1 で :Resync を呼ぶ(ide() が kill -USR1 を送る)。

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
