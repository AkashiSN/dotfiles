return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master", -- クラシック API（configs + ensure_installed）を使う
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      { "nvim-treesitter/nvim-treesitter-textobjects", branch = "master" },
    },
    main = "nvim-treesitter.configs",
    opts = {
      -- C コンパイラが必要。bare な環境向けに自動インストールは無効
      auto_install = false,
      ensure_installed = {
        "lua", "vim", "vimdoc", "bash",
        "go", "gomod", "gosum", "gowork",
        "typescript", "tsx", "javascript",
        "python", "terraform", "hcl",
        "json", "yaml", "toml", "markdown", "markdown_inline",
      },
      highlight = { enable = true },
      indent = { enable = true },
      textobjects = {
        select = {
          enable = true,
          lookahead = true,
          keymaps = {
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
            ["ac"] = "@class.outer",
            ["ic"] = "@class.inner",
          },
        },
      },
    },
  },
}
