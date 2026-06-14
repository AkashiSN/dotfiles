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
