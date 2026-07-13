return {
  -- mason: LSP サーバ等のインストーラ
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    opts = {
      ui = { border = "rounded" },
    },
  },

  -- mason と lspconfig の橋渡し（ensure_installed + 自動有効化）
  {
    "mason-org/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    opts = {
      ensure_installed = {
        "lua_ls",
        "gopls",
        "ts_ls",
        "pyright",
        "terraformls",
        "bashls",
      },
      automatic_enable = true, -- mason-lspconfig 2.x が vim.lsp.enable() を自動呼出
    },
  },

  -- nvim-lspconfig: サーバ設定（Neovim 0.11 native API）+ LspAttach キーマップ
  {
    "neovim/nvim-lspconfig",
    config = function()
      -- blink.cmp の capabilities を全サーバに付与
      local caps = require("blink.cmp").get_lsp_capabilities()
      vim.lsp.config("*", { capabilities = caps })

      -- サーバ個別設定
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim", "Snacks" } },
            workspace = { checkThirdParty = false },
          },
        },
      })
      vim.lsp.config("pyright", {
        settings = {
          python = { analysis = { typeCheckingMode = "basic" } },
        },
      })

      -- ruff は aqua 管理 (mason 経由ではない) ので、mason-lspconfig の
      -- automatic_enable では有効化されない。ここで明示的に有効化する。
      vim.lsp.enable("ruff")

      -- LspAttach 時にバッファローカルなキーマップを張る
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lsp_attach_keymaps", { clear = true }),
        callback = function(ev)
          local function map(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
          end
          map("K", vim.lsp.buf.hover, "Hover")
          map("gd", vim.lsp.buf.definition, "Go to definition")
          map("gD", vim.lsp.buf.declaration, "Go to declaration")
          map("gr", vim.lsp.buf.references, "References")
          map("gi", vim.lsp.buf.implementation, "Implementation")
          map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>cd", vim.diagnostic.open_float, "Line diagnostics")
          map("[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Prev diagnostic")
          map("]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")
        end,
      })
    end,
  },
}
