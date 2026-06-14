-- Neovim 0.12 で tree-sitter がコアへ統合され、nvim-treesitter は 2026-04 に
-- アーカイブされた。master(classic) ブランチは 0.12 非対応 (injection 処理で
-- `attempt to call method 'range'` エラー) のため、構成を以下へ移行した:
--   * パーサー/ハイライトクエリ管理 … tree-sitter-manager.nvim (アクティブメンテ)
--   * シンタックスハイライト        … tree-sitter-manager が自動有効化
--   * テキストオブジェクト          … nvim-treesitter-textobjects(main) を単独利用
--                                     (本体非依存・自前の textobjects.scm を同梱)
-- パーサーのビルドに tree-sitter CLI (aqua 管理)・git・C コンパイラが必要。

local parsers = {
  "lua", "vim", "vimdoc", "bash",
  "go", "gomod", "gosum", "gowork",
  "typescript", "tsx", "javascript",
  "python", "terraform", "hcl",
  "json", "yaml", "toml", "markdown", "markdown_inline",
}

return {
  -- パーサー/クエリ管理 + ハイライト
  {
    "romus204/tree-sitter-manager.nvim",
    lazy = false,
    config = function()
      require("tree-sitter-manager").setup({
        ensure_installed = parsers,
        auto_install = false, -- 列挙したものだけ。未知の filetype では自動取得しない
        highlight = true, -- vim.treesitter ハイライトを自動有効化
      })
    end,
  },

  -- テキストオブジェクト (af/if/ac/ic) — 本体非依存で動く
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    lazy = false,
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
      })

      local sel = require("nvim-treesitter-textobjects.select").select_textobject
      local function map(lhs, obj, desc)
        vim.keymap.set({ "x", "o" }, lhs, function()
          sel(obj, "textobjects")
        end, { desc = desc })
      end
      map("af", "@function.outer", "around function")
      map("if", "@function.inner", "inside function")
      map("ac", "@class.outer", "around class")
      map("ic", "@class.inner", "inside class")
    end,
  },
}
