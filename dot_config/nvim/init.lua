-- Neovim config (VSCode-like, Leader-based)
-- leader はプラグイン読み込み前に設定する必要がある
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
require("config.ide")
