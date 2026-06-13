return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000, -- カラースキームは最優先で読み込む
    opts = {
      flavour = "mocha",
      integrations = {
        treesitter = true,
        native_lsp = { enabled = true },
        gitsigns = true,
        neotree = true,
        which_key = true,
        mason = true,
        blink_cmp = true,
        bufferline = true,
        indent_blankline = { enabled = true },
        snacks = true,
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },
}
