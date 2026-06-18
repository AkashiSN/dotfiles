-- 外部ファイル変更の自動同期（未編集バッファの静かな自動リロード）
-- autoread が未編集バッファを自動でリロードする。編集中バッファが外部変更された
-- 場合の扱いは vim 標準の警告（保存時の E13 など）に任せる。

local group = vim.api.nvim_create_augroup("external_sync", { clear = true })

-- 外部変更を検知したら未編集バッファを自動でリロードする
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
