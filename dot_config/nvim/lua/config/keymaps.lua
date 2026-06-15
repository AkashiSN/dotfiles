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

-- ダブルクリックでそのウィンドウにフォーカスを移しつつ自動で挿入モードに入る
-- (VSCode ライクなモードレス感覚)。毎回 i を押す手間がなくなり、IME が全角の
-- ままでも半角へ戻して i を押す必要がなくなる。
--   通常の編集バッファ      … 挿入モード
--   ターミナル(claude/下部)  … ターミナルジョブモード(そのまま打てる)
--   neo-tree/ダッシュボード等 … 何もしない(ツリー操作などを維持)
-- シングルクリックは既定動作(フォーカス移動+カーソル位置決めのみ)に任せる。
-- これにより、ターミナルのログをシングルクリック+ドラッグでビジュアル選択して
-- y でコピーできる(以前のシングルクリック→即 insert だと terminal-job モードへ
-- 入ってしまい選択コピーできなかった)。ダブルクリックの1回目で既にカーソルが
-- 位置決めされているので、2 回目(<2-LeftMouse>)で startinsert すれば足りる。
-- vim.g.click_to_insert = false で無効化できる。
vim.g.click_to_insert = true
map("n", "<2-LeftMouse>", function()
  if not vim.g.click_to_insert then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local bt = vim.bo[buf].buftype
  if bt == "terminal" then
    vim.cmd("startinsert")
  elseif bt == "" and vim.bo[buf].modifiable and not vim.bo[buf].readonly then
    vim.cmd("startinsert")
  end
end, { desc = "Focus pane by double-click then enter insert" })
