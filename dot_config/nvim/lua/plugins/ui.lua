return {
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- ステータスライン
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = "catppuccin-mocha", -- catppuccin はフレーバー別テーマ名を使う
        globalstatus = true,
        section_separators = "",
        component_separators = "|",
      },
    },
  },

  -- タブライン（バッファをタブ表示）
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },
      { "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev buffer" },
      { "<leader>bp", "<cmd>BufferLinePick<cr>", desc = "Pick buffer" },
    },
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        offsets = {
          { filetype = "neo-tree", text = "Explorer", separator = true },
        },
      },
    },
  },

  -- インデントガイド
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    opts = { scope = { enabled = true } },
  },

  -- 括弧の虹色
  {
    "HiPhish/rainbow-delimiters.nvim",
    event = { "BufReadPost", "BufNewFile" },
  },

  -- which-key（キーマップヘルプ）
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>f", group = "find" },
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>g", group = "git" },
        { "<leader>t", group = "terminal" },
      },
    },
  },

  -- snacks: dashboard + terminal + バッファ削除
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      dashboard = { enabled = true },
      terminal = { enabled = true },
      bufdelete = { enabled = true },
    },
    keys = {
      { "<leader>t", function() Snacks.terminal() end, desc = "Terminal (toggle)" },
      { "<C-/>", function() Snacks.terminal() end, mode = { "n", "t" }, desc = "Terminal (toggle)" },
      { "<C-_>", function() Snacks.terminal() end, mode = { "n", "t" }, desc = "which_key_ignore" },
      { "<leader>bd", function() Snacks.bufdelete() end, desc = "Delete buffer" },
    },
  },
}
