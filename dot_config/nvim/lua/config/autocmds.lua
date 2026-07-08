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

-- shpool 再アタッチ時の表示崩れ / マウス不作動を復旧する。
-- 原因: nvim は in-band resize(DEC private mode 2048)対応端末(Ghostty)を検出すると、
-- 以後 SIGWINCH ではなく in-band のリサイズ通知だけを見るようになる。shpool は in-band
-- リサイズを生成できず、reattach 時は SIGWINCH しか送れないため、別サイズで再接続すると
-- nvim が新サイズに追従できず表示が崩れる。マウスも同様に、有効化シーケンスが新しい端末へ
-- 伝わっておらず効かなくなる。
-- 対策: mode 2048 を再アームして端末に現在サイズを再報告させ(→ nvim が正しいサイズに追従)、
-- マウス有効化シーケンスを再送する。shpool は reattach のたび SIGWINCH を送るので、Signal
-- SIGWINCH の autocmd に紐づければ ide 関数の介入なしで自動化できる。手動用に :Resync も公開。
local function resync()
  io.stdout:write("\027[?2048h")   -- in-band resize を再アーム → 端末が現在サイズを再報告
  local m = vim.o.mouse
  vim.o.mouse = ""
  vim.o.mouse = m                   -- マウス有効化シーケンスを再送
end
vim.api.nvim_create_user_command("Resync", resync, {})
local running = false
vim.api.nvim_create_autocmd("Signal", {
  pattern = "SIGWINCH",
  callback = function()
    if running then return end
    running = true
    vim.schedule(function() resync(); running = false end)
  end,
})
