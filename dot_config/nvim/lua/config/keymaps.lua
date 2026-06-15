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

-- ダブルクリック / Enter でアクティブなペインを自動で入力可能にする
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
-- 入力可能なバッファなら挿入(ターミナルジョブ)モードへ入り true を返す。
-- それ以外(neo-tree/quickfix/ダッシュボード等)は何もせず false を返す。
local function enter_insert_on_focus()
  if not vim.g.click_to_insert then
    return false
  end
  local buf = vim.api.nvim_get_current_buf()
  local bt = vim.bo[buf].buftype
  if bt == "terminal" then
    vim.cmd("startinsert")
    return true
  elseif bt == "" and vim.bo[buf].modifiable and not vim.bo[buf].readonly then
    vim.cmd("startinsert")
    return true
  end
  return false
end

map("n", "<2-LeftMouse>", function()
  enter_insert_on_focus()
end, { desc = "Focus pane by double-click then enter insert" })

-- アクティブなペインで Enter を押したらダブルクリックと同じく挿入モードへ。
-- 入力可能でないバッファ(quickfix で項目へジャンプ等)では既定の <CR> に委譲する。
-- neo-tree など buffer-local の <CR> を持つバッファはそちらが優先されるため影響なし。
map("n", "<CR>", function()
  if not enter_insert_on_focus() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
  end
end, { desc = "Enter insert mode in active pane (else default <CR>)" })
