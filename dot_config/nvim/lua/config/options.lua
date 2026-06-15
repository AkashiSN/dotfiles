-- 基本オプション
local opt = vim.opt

opt.number = true
opt.relativenumber = false
opt.signcolumn = "yes"
opt.cursorline = true
opt.termguicolors = true
opt.mouse = "a"
opt.scrolloff = 8
opt.wrap = false

-- インデント（プロジェクト規約: tab=4, spaces）
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.smartindent = true

-- 検索
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- ファイル
opt.undofile = true
opt.swapfile = false
opt.fileencoding = "utf-8"

-- 分割の向き（VSCode 感覚）
opt.splitright = true
opt.splitbelow = true

-- diff 表示（diffview / vimdiff 共通）
-- 既定の fillchars は diff:- で、片側にしか行が無い「埋め草行」が
-- ハイフン(やスラッシュ)の壁になり見にくい。埋め草行の文字を空白にして、
-- catppuccin の DiffDelete が持つ赤系背景だけが残るようにする。
opt.fillchars:append({ diff = " " })
-- linematch: 変更行どうしを賢く対応付けし、行内の差分だけを色付け
-- (ブロック丸ごとが差分扱いになりにくく、行単位の違いが見やすい)。
opt.diffopt:append("linematch:60")

-- 補完・UI
opt.completeopt = "menu,menuone,noselect"
opt.updatetime = 250
opt.timeoutlen = 400
opt.winminwidth = 5

-- クリップボード: ローカル mac は native(pbcopy/pbpaste)、SSH 越しは OSC52
opt.clipboard = "unnamedplus"
local in_ssh = (vim.env.SSH_CONNECTION ~= nil) or (vim.env.SSH_TTY ~= nil)
if in_ssh then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok then
    vim.g.clipboard = {
      name = "OSC52",
      copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
      paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
    }
  end
end

-- 診断表示
vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = "rounded" },
})
