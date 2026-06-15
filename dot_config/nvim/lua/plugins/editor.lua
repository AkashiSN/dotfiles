return {
  -- ファイルエクスプローラ
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    cmd = "Neotree",
    keys = {
      -- トグル: 開いていれば閉じる(閉じると IDE モードでは右の claude ペインが
      -- 画面幅の 50% まで広がる / 開くと残り幅を 50/50 に取り直す)。
      { "<leader>e", "<cmd>Neotree toggle filesystem left<cr>", desc = "Explorer toggle" },
      { "<leader>E", "<cmd>Neotree reveal<cr>", desc = "Explorer reveal file" },
      -- VSCode のソース管理パネル相当: 左ツリーを Git モードに切り替える
      { "<leader>gg", "<cmd>Neotree git_status left<cr>", desc = "Git status panel" },
    },
    opts = {
      close_if_last_window = true,
      sources = { "filesystem", "buffers", "git_status" },
      -- 上部にクリック可能なタブ(Files / Buffers / Git)を表示。
      -- マウスでタブをクリックして左ツリーの表示ソースを切り替えられる。
      source_selector = {
        winbar = true,
        statusline = false,
        sources = {
          { source = "filesystem", display_name = "  Files " },
          { source = "buffers", display_name = "  Buffers " },
          { source = "git_status", display_name = "  Git " },
        },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = { hide_dotfiles = false, hide_gitignored = false },
      },
      git_status = {
        window = {
          mappings = {
            -- 変更ファイルを選ぶと diffview を専用タブで開く(左=HEAD / 右=作業ツリー)。
            -- diffview は1つの vim タブページとして開くので、別ファイルを編集して
            -- 戻ってきても diff 状態は失われない。見終わったら diffview 内で `q`
            -- または <leader>gq (:DiffviewClose) で閉じると元のレイアウトに戻る。
            -- (キーボードの <cr> でもマウスのダブルクリックでも)
            ["<cr>"] = "diff_in_editor",
            ["<2-LeftMouse>"] = "diff_in_editor",
            -- 差分にせず通常どおりファイルを開きたいとき
            ["o"] = "open",
          },
        },
      },
      commands = {
        -- neo-tree の Git タブで選んだファイルを diffview の専用タブで開く。
        -- 全変更ファイルをまとめて見たいときは <leader>gd を使う。
        diff_in_editor = function(state)
          local node = state.tree:get_node()
          if not node or node.type ~= "file" then
            return
          end
          -- `-- <path>` で対象ファイルだけにスコープした作業ツリー vs HEAD 差分。
          vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(node.path))
        end,
      },
      window = {
        width = 32,
        mappings = {
          ["<space>"] = "none", -- leader と衝突させない
        },
      },
    },
    config = function(_, opts)
      require("neo-tree").setup(opts)

      -- 5秒ごとに表示中の neo-tree ソースの Git ステータスを再計算する。
      -- neo-tree はイベント駆動で定期ポーリングしないため、外部コマンド
      -- (git commit / pull / checkout など、作業ツリーのファイルを書き換え
      -- ない操作)では左ツリーの変更マーカー(色)が古いまま残る。これを定期
      -- 更新で追従させる。ツリーが画面に出ているソースだけ refresh し、
      -- 閉じている間は無駄な git 起動をしない。
      local timer = (vim.uv or vim.loop).new_timer()
      timer:start(5000, 5000, vim.schedule_wrap(function()
        local ok, manager = pcall(require, "neo-tree.sources.manager")
        if not ok then
          return
        end
        for _, source in ipairs({ "filesystem", "git_status" }) do
          local sok, state = pcall(manager.get_state, source)
          if sok and state and state.winid and vim.api.nvim_win_is_valid(state.winid) then
            pcall(manager.refresh, source)
          end
        end
      end))
    end,
  },

  -- ファジーファインダー（fzf-lua）
  {
    "ibhagwan/fzf-lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "FzfLua",
    keys = {
      { "<leader><space>", "<cmd>FzfLua files<cr>", desc = "Find files" },
      { "<leader>ff", "<cmd>FzfLua files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>FzfLua live_grep<cr>", desc = "Live grep" },
      { "<leader>/", "<cmd>FzfLua live_grep<cr>", desc = "Live grep" },
      { "<leader>fr", "<cmd>FzfLua oldfiles<cr>", desc = "Recent files" },
      { "<leader>fb", "<cmd>FzfLua buffers<cr>", desc = "Buffers" },
      { "<leader>fc", "<cmd>FzfLua commands<cr>", desc = "Commands" },
      { "<leader>fh", "<cmd>FzfLua help_tags<cr>", desc = "Help tags" },
      { "<leader>fR", "<cmd>FzfLua resume<cr>", desc = "Resume picker" },
      { "<leader>cs", "<cmd>FzfLua lsp_document_symbols<cr>", desc = "Document symbols" },
      { "<leader>cD", "<cmd>FzfLua diagnostics_workspace<cr>", desc = "Workspace diagnostics" },
    },
    opts = {},
  },

  -- git 行マーク
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(buffer)
        local gs = require("gitsigns")
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
        end
        map("n", "]h", gs.next_hunk, "Next hunk")
        map("n", "[h", gs.prev_hunk, "Prev hunk")
        map("n", "<leader>gs", gs.stage_hunk, "Stage hunk")
        map("n", "<leader>gr", gs.reset_hunk, "Reset hunk")
        map("n", "<leader>gp", gs.preview_hunk, "Preview hunk")
        map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")
      end,
    },
  },

  -- diff / ファイル履歴 (サイドバイサイド差分・ステージング)
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFileHistory" },
    keys = {
      -- 作業ツリー vs HEAD の差分を開く
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview (working tree)" },
      { "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diffview close" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history (current)" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "File history (repo)" },
    },
    -- diffview のファイルパネル内では既定で以下が使える:
    --   -  : カーソル下のファイル/hunk を stage / unstage
    --   S  : 全て stage    U : 全て unstage
    --   X  : 変更を破棄    R : 全ファイル refresh
    opts = {
      -- diffview のタブを見ている間は上部のファイルタブ(bufferline)を隠す。
      -- (出ていると誤ってタブをクリックした際、diff ウィンドウに通常ファイルが
      --  読み込まれてレイアウトが壊れ戻れなくなるため)。diffview は専用タブ
      --  ページなので、そのタブに入ったら隠し・離れたら(=他タブ/閉じる)戻す。
      hooks = {
        view_enter = function() vim.o.showtabline = 0 end,
        view_leave = function() vim.o.showtabline = 2 end,
        view_closed = function() vim.o.showtabline = 2 end,
      },
      keymaps = {
        -- diff/パネルどこでも `q` で確実に diffview ごと閉じて元に戻る。
        -- (IDE モードでは :q が SmartQ に化けて片ペインだけ消える事故が
        --  起きるため、専用に潰しておく)
        view = {
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },
        },
        file_panel = {
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },
        },
        file_history_panel = {
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },
        },
      },
    },
  },

  -- tmux pane とのシームレス移動
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
    },
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to left window" },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to lower window" },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to upper window" },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to right window" },
    },
  },
}
