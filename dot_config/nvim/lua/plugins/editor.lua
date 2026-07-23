-- プラグイン標準ヘルプ(英語・全キー羅列)の代わりに「よく使うキー」だけを
-- 日本語フロートで表示するための共通ヘルパー。中央に角丸ボーダーで出し、
-- q / <esc> / ? のいずれでも閉じられる(再表示も同じ `?`)。filetype を
-- 受け取り、呼び出し元ごとに区別できるようにする。
local function open_cheat_float(lines, title, filetype)
  local width = 2
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
  end
  local height = #lines
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = filetype
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })
  vim.wo[win].cursorline = false
  for _, key in ipairs({ "q", "<esc>", "?" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true })
  end
end

-- diffview の「よく使うキー」を日本語フロートで表示するミニヘルプ。
-- 標準ヘルプ(g?)はペイン別かつ英語・項目過多で目的のキーを探しにくいため、
-- ファイルパネルで `?` を押すと、実際にそのパネルで効くキーだけを日本語で出す。
-- (差分ウィンドウ側では `?` は素の後方検索のまま残す)
local function diffview_cheat()
  open_cheat_float({
    "  diffview よく使うキー（ファイルパネル）",
    "",
    "  - / s      ファイルを stage / unstage",
    "  S          全ファイルを stage",
    "  U          全ファイルを unstage",
    "  X          変更を破棄（左の状態に戻す）",
    "  R          一覧を再読み込み",
    "  <cr> / o   カーソル下の差分を開く",
    "  <tab>      次の変更ファイルの差分",
    "  <s-tab>    前の変更ファイルの差分",
    "  <leader>e  ファイルパネルへフォーカス",
    "  <leader>b  ファイルパネルの表示切替",
    "  g?         標準ヘルプ（全キー・英語）",
    "  q          diffview を閉じる",
    "",
    "  ? で再表示 / q・<esc> でこのヘルプを閉じる",
  }, " diffview cheat ", "diffview_cheat")
end

-- neo-tree の標準ヘルプ(`?`=show_help)も英語・全キー羅列で探しにくいため、
-- diffview と同じ流儀で `?` を日本語ミニヘルプに差し替える(標準ヘルプは g? へ退避)。
-- 表示中のソース(state.name)で内容を出し分け、Files / Buffers / Git それぞれで
-- 実際に効くキーだけを出す。Git の `<cr>`(diffview を開く)・`o`(通常オープン)・
-- 全ソースで無効化した `<space>` など、本設定の独自オーバーライドも反映済み。
local function neotree_cheat(state)
  local footer = {
    "",
    "  ? で再表示 / q・<esc> でこのヘルプを閉じる",
  }
  -- どのソースでも共通の末尾キー(ソース切替・標準ヘルプ・閉じる)。
  -- 並び替え `o…` は Files / Buffers のみ(Git では `o` を通常オープンに上書き)。
  local common_tail = {
    "  i          ファイル詳細",
    "  R          一覧を再読み込み",
    "  < / >      ソース切替（Files / Buffers / Git）",
    "  g?         標準ヘルプ（全キー・英語）",
    "  q          ツリーを閉じる",
  }
  local sources = {
    filesystem = {
      title = " neo-tree cheat (Files) ",
      body = {
        "  neo-tree よく使うキー（Files）",
        "",
        "  <cr>       開く / フォルダを展開・折りたたみ",
        "  l          プレビューへフォーカス  P プレビュー(フロート)切替",
        "  S / s      水平 / 垂直分割で開く   t 新規タブで開く",
        "  C / z      ノードを閉じる / 全て閉じる",
        "  <bs>       親ディレクトリへ        . カーソル位置をルートに",
        "  H          隠しファイル表示切替",
        "  /          ファジー検索   f 絞り込み確定   <c-x> 解除",
        "  a / A      ファイル / ディレクトリ作成",
        "  r / b      リネーム / ベース名リネーム   d 削除",
        "  y / x / p  コピー / カット / 貼り付け",
        "  c / m      コピー / 移動（宛先を入力）",
        "  [g / ]g    前 / 次の Git 変更へ",
        "  o…         並び替え(on:名前 om:更新 os:サイズ od:診断 ...)",
      },
    },
    buffers = {
      title = " neo-tree cheat (Buffers) ",
      body = {
        "  neo-tree よく使うキー（Buffers）",
        "",
        "  <cr>       バッファを開く",
        "  d / bd     バッファを削除（閉じる）",
        "  S / s      水平 / 垂直分割で開く   t 新規タブで開く",
        "  <bs>       親ディレクトリへ        . カーソル位置をルートに",
        "  o…         並び替え(on:名前 om:更新 os:サイズ ...)",
      },
    },
    git_status = {
      title = " neo-tree cheat (Git) ",
      body = {
        "  neo-tree よく使うキー（Git）",
        "",
        "  <cr>       diffview で差分を開く（専用タブ・本設定の独自キー）",
        "  o          差分にせず通常どおりファイルを開く",
        "  ga / gu    カーソル下を stage / unstage",
        "  A          全ファイルを stage   gt ステージ切替(トグル)",
        "  gr         変更を破棄（revert）",
        "  gc / gp    コミット / push   gg コミットして push",
        "  gU         直前のコミットを取り消し",
      },
    },
  }
  local spec = sources[state and state.name] or sources.filesystem
  local lines = {}
  for _, l in ipairs(spec.body) do
    lines[#lines + 1] = l
  end
  for _, l in ipairs(common_tail) do
    lines[#lines + 1] = l
  end
  for _, l in ipairs(footer) do
    lines[#lines + 1] = l
  end
  open_cheat_float(lines, spec.title, "neotree_cheat")
end

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
      -- トグル: 開いていれば閉じる。
      { "<leader>e", "<cmd>Neotree toggle filesystem left<cr>", desc = "Explorer toggle" },
      { "<leader>E", "<cmd>Neotree reveal<cr>", desc = "Explorer reveal file" },
      -- VSCode のソース管理パネル相当: 左ツリーを Git モードに切り替える
      { "<leader>gg", "<cmd>Neotree git_status left<cr>", desc = "Git status panel" },
    },
    opts = {
      close_if_last_window = true,
      sources = { "filesystem", "buffers", "git_status" },
      -- neo-tree からファイルを開くとき、これらの種別の窓は開く先にせず別窓に開く。
      -- "terminal" を含めることで、フォーカス中のペインが端末でもそれを潰さない
      -- (LazyVim 既定の挙動)。
      open_files_do_not_replace_types = { "Trouble", "qf", "edgy", "terminal" },
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
            -- 全変更ファイルを一覧した状態で開き、選んだファイルへフォーカスする
            -- (Git タブの一覧と diffview のファイルパネルが一致する)。diffview は
            -- 1つの vim タブページとして開くので、別ファイルを編集して戻ってきても
            -- diff 状態は失われない。見終わったら diffview 内で `q` または
            -- <leader>gq (:DiffviewClose) で閉じると元のレイアウトに戻る。
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
        -- 全変更ファイルを一覧した状態(<leader>gd と同じ)で開き、選んだファイルに
        -- フォーカスする。これで diffview のファイルパネルと Git タブの一覧が一致する。
        diff_in_editor = function(state)
          local node = state.tree:get_node()
          if not node or node.type ~= "file" then
            return
          end
          local target = vim.fs.normalize(node.path) -- neo-tree ノードの絶対パス
          -- スコープを付けず全変更ファイルで開く(作業ツリー vs HEAD)。
          vim.cmd("DiffviewOpen")
          -- diffview のファイル一覧は非同期で構築されるため、揃うまで待ってから
          -- 対象ファイルへフォーカス(highlight=true でパネル側のカーソルも移動)。
          local lib = require("diffview.lib")
          local tries = 0
          local function focus_target()
            tries = tries + 1
            local view = lib.get_current_view()
            if view and view.files and view.files:len() > 0 then
              for _, file in view.files:iter() do
                if file.absolute_path and vim.fs.normalize(file.absolute_path) == target then
                  view:set_file(file, false, true)
                  return
                end
              end
              return -- 一覧は揃ったが対象が見つからない(稀)→先頭のまま
            end
            if tries < 50 then
              vim.defer_fn(focus_target, 20)
            end
          end
          vim.defer_fn(focus_target, 20)
        end,
      },
      window = {
        width = 32,
        mappings = {
          ["<space>"] = "none", -- leader と衝突させない
          -- 標準ヘルプ(`?`=show_help)は英語・全キー羅列で探しにくいため、diffview と
          -- 同じ流儀で `?` を日本語ミニヘルプ(ソース別に出し分け)へ差し替える。
          -- 英語の全キー一覧は g? に退避(g 始まりの git キーとはプレフィックス衝突しない)。
          ["?"] = neotree_cheat,
          ["g?"] = "show_help",
        },
      },
    },
    config = function(_, opts)
      require("neo-tree").setup(opts)

      -- 5秒ごとに neo-tree の Git ステータスを再計算する(定期ポーリング)。
      -- neo-tree は .git ディレクトリ監視(git/watch.lua)と libuv ファイル監視で
      -- 変更を検知するが、(1) macOS のフォルダ監視は「ファイル内容だけが外部で
      -- 書き換わった(ディレクトリエントリは不変)」変更を取りこぼしやすく、
      -- (2) commit/checkout などでも検知が漏れる場合があるため、左ツリーの変更
      -- マーカー(色)が古いまま残ることがある。これを定期更新で確実に追従させる。
      --
      -- 更新には neo-tree 自身の正規シグナル GIT_EVENT を発火する(git ディレクトリ
      -- 監視が外部 git 操作を検知したときに発火させるのと同じもの)。これにより
      -- filesystem / buffers / git_status の各ソースが neo-tree のハンドラ経由で
      -- git status を再実行し、マーカーを描き直す。表示中の窓が無いときは何もせず、
      -- 閉じている間は無駄な git 起動をしない。
      local timer = (vim.uv or vim.loop).new_timer()
      timer:start(5000, 5000, vim.schedule_wrap(function()
        -- 現在のタブに neo-tree の窓が出ているときだけ更新する。
        local visible = false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].filetype == "neo-tree" then
            visible = true
            break
          end
        end
        if not visible then
          return
        end
        local ok, events = pcall(require, "neo-tree.events")
        if ok then
          pcall(events.fire_event, events.GIT_EVENT)
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
    -- これらを日本語でまとめたミニヘルプを `?`(ファイルパネル/履歴パネル)に割り当て。
    -- パネル左上の "Help: <key>" ヒントは desc が "Open the help panel" の
    -- マッピングのキーを表示する仕様なので、その desc を `?`(ミニヘルプ)側に付け
    -- 替えてヒントを `?` にする。標準の英語ヘルプは `g?` のまま残す(desc だけ変更)。
    opts = function()
      local actions = require("diffview.actions")
      return {
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
          view = {
            { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },
          },
          file_panel = {
            { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },
            -- `?` を「ヘルプ」として認識させる(desc がヒント判定に使われる)。
            { "n", "?", diffview_cheat, { desc = "Open the help panel" } },
            -- 標準の英語ヘルプは g? のまま残すが、ヒントに拾われないよう desc を変更。
            { "n", "g?", actions.help("file_panel"), { desc = "標準ヘルプ(全キー・英語)" } },
          },
          file_history_panel = {
            { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },
            { "n", "?", diffview_cheat, { desc = "Open the help panel" } },
            { "n", "g?", actions.help("file_history_panel"), { desc = "標準ヘルプ(全キー・英語)" } },
          },
        },
      }
    end,
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
