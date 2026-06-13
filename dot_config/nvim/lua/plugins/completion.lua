return {
  {
    "saghen/blink.cmp",
    version = "1.*", -- プリビルトのファジーマッチャを使う（Rust ビルド不要）
    event = "InsertEnter",
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = { preset = "default" }, -- <C-y> 確定, <C-space> 補完, <C-n>/<C-p> 選択
      appearance = { nerd_font_variant = "mono" },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        accept = { auto_brackets = { enabled = true } },
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      signature = { enabled = true },
    },
  },
}
