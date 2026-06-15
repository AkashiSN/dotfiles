-- chezmoi のソースファイル名から属性接頭辞や .tmpl などを取り除き、
-- 「展開後の実ファイル名」で filetype を判定する。
-- これにより dot_/private_ 等が付いていても通常どおり色がつく。
--   例: private_dot_zshrc -> .zshrc -> zsh
--       dot_zshenv.tmpl   -> .zshenv -> zsh
--       run_once_..._macos.sh.tmpl -> ....sh -> sh

-- chezmoi の属性接頭辞（dot_ は後段で別途 . へ変換する）
local attr_prefixes = {
  "encrypted_",
  "private_",
  "readonly_",
  "executable_",
  "empty_",
  "exact_",
  "literal_",
  "symlink_",
}

-- ソース名 -> 実ファイル名。chezmoi 装飾が無く変化しなければ nil を返す。
local function chezmoi_target(name)
  local original = name
  -- 末尾の .tmpl / .literal を除去
  name = name:gsub("%.tmpl$", ""):gsub("%.literal$", "")
  -- 先頭の属性接頭辞を繰り返し除去（private_readonly_ のような連結に対応）
  local changed = true
  while changed do
    changed = false
    for _, p in ipairs(attr_prefixes) do
      if name:sub(1, #p) == p then
        name = name:sub(#p + 1)
        changed = true
      end
    end
  end
  -- dot_ -> .
  if name:sub(1, 4) == "dot_" then
    name = "." .. name:sub(5)
  end
  if name == original then
    return nil -- chezmoi 装飾なし。通常の filetype 判定に任せる
  end
  return name
end

vim.filetype.add({
  pattern = {
    -- グローバル gitignore は実名 (.gitignore_global) にコアの判定が無いので補う
    [".*gitignore.*"] = "gitignore",
    -- 高優先度で全ファイルを受け、chezmoi 装飾があるときだけ実名で再判定する。
    -- ここを高くしないと .tmpl が組み込みの template 判定に奪われる。
    -- 装飾が無ければ nil を返し、組み込み判定へフォールスルーする
    -- （実名 .zshrc 等は装飾無し → 再帰せず組み込みが効く）。
    [".*"] = {
      function(path)
        local name = vim.fn.fnamemodify(path, ":t")
        local target = chezmoi_target(name)
        if not target then
          return nil
        end
        -- match は (filetype, on_detect) を返すので両方引き継ぐ（bash 等）
        return vim.filetype.match({ filename = target })
      end,
      { priority = 100 },
    },
  },
})
