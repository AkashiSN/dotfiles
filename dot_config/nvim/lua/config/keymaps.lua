-- プラグイン非依存の Leader キーマップ
local map = vim.keymap.set

-- 保存・終了
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })

-- 検索ハイライト解除
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- バッファ移動（タブ感覚）— bufferline 側でも上書きするが素の動作も用意
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })

-- フォーマット（LSP）
map({ "n", "v" }, "<leader>cf", function()
  vim.lsp.buf.format({ async = true })
end, { desc = "Format" })

-- ビジュアルモードでインデントを保持
map("v", "<", "<gv")
map("v", ">", ">gv")
