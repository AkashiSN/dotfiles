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
-- 原因: nvim は in-band resize(DEC private mode 2048)対応端末(Ghostty)では SIGWINCH ではなく
-- in-band のリサイズ通知でサイズを追う。shpool は in-band リサイズを生成せず、別サイズで reattach
-- してもそれを nvim へ伝えないため、新サイズに追従できず表示が崩れ、マウス有効化シーケンスも新しい
-- 端末へ伝わらず効かなくなる。
-- 対策:
--   * mode 2048 を再アーム(\027[?2048h) → 端末が現在サイズを in-band で再報告し、nvim が追従する。
--   * マウス有効化シーケンスを再送する。off→on を別 tick に分けてそれぞれフラッシュさせるのが要点:
--     同一 tick で off→on すると nvim は差し引き無変化とみなし DECRST/DECSET を一切出さず、再送に
--     ならない。resize が落ち着いてから撃つよう少し遅らせる。
-- 自動起動(reattach 検知)は ide.lua が Signal SIGUSR1 で :Resync を呼ぶ(ide() が kill -USR1 を送る)。
local function resync()
  io.stdout:write("\027[?2048h")
  local m = vim.o.mouse
  vim.defer_fn(function()
    vim.o.mouse = ""                                -- 無効化(この tick でフラッシュ → DECRST 送出)
    vim.schedule(function() vim.o.mouse = m end)    -- 次 tick で有効化 → DECSET 送出
  end, 80)
end
vim.api.nvim_create_user_command("Resync", resync, {})
