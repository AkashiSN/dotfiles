-- 外部ファイル変更の自動同期 + 保存時コンフリクト解決
-- 挙動A: 未編集バッファは外部変更を検知して静かに自動リロード
-- 挙動B: 編集中バッファは保存時に検知して .bak 退避 + 3択（Task 2 で実装）

local group = vim.api.nvim_create_augroup("external_sync", { clear = true })

-- 外部変更を検知したら自動でバッファに反映する
vim.opt.autoread = true

-- nvim は常時監視しないので、フォーカス・バッファ移動・無操作で :checktime を発火する
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermLeave" }, {
  group = group,
  callback = function()
    -- コマンドラインモード中など checktime が使えない状況では何もしない
    if vim.fn.mode() ~= "c" then
      pcall(vim.cmd.checktime)
    end
  end,
})

-- 外部変更検知時のハンドラ: 未編集なら静かにリロード（挙動A）
vim.api.nvim_create_autocmd("FileChangedShell", {
  group = group,
  callback = function()
    if not vim.bo.modified then
      vim.v.fcs_choice = "reload"
    end
    -- 編集中の分岐は Task 2 で追加する
  end,
})
