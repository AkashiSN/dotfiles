-- IDE モード: `NVIM_IDE=1 nvim`（引数なし）起動時に VSCode ライクなレイアウトを
-- 自動展開する。env は起動直後に nil 化して子プロセス(ターミナル等)へ伝播させない。

local function count_real_buffers()
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted and vim.bo[b].buftype == "" then
      n = n + 1
    end
  end
  return n
end

-- :q / :wq を賢く: 最後の実バッファを閉じても終了せずダッシュボードへ戻る
vim.api.nvim_create_user_command("SmartQ", function()
  local last = count_real_buffers() <= 1
  pcall(function() Snacks.bufdelete() end)
  -- 最後の実バッファなら現在ウィンドウ内にダッシュボードを表示(終了しない)
  if last then
    pcall(function() Snacks.dashboard.open({ win = 0 }) end)
  end
end, { desc = "Close buffer; return to dashboard if it was the last" })

vim.api.nvim_create_user_command("SmartWQ", function()
  pcall(vim.cmd.write)
  vim.cmd("SmartQ")
end, { desc = "Write then SmartQ" })

local function open_terminal(split_cmd, size_cmd)
  vim.cmd(split_cmd)
  vim.cmd("terminal")
  if size_cmd then vim.cmd(size_cmd) end
  vim.bo.buflisted = false
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.opt_local.signcolumn = "no"
end

local function start_layout()
  local dash = vim.api.nvim_get_current_win()

  -- 右ターミナル(全高・画面幅の約30%)
  open_terminal("botright vsplit", "vertical resize " .. math.max(40, math.floor(vim.o.columns * 0.30)))

  -- 下ターミナル(メイン領域の下・画面高の約28%)
  if vim.api.nvim_win_is_valid(dash) then
    vim.api.nvim_set_current_win(dash)
  end
  open_terminal("belowright split", "resize " .. math.max(8, math.floor(vim.o.lines * 0.28)))

  -- ファイルツリー(左)
  pcall(vim.cmd, "Neotree show left")

  -- メインウィンドウ内にダッシュボードを表示してフォーカスを戻す(フロートにしない)
  if vim.api.nvim_win_is_valid(dash) then
    vim.api.nvim_set_current_win(dash)
    pcall(function() Snacks.dashboard.open({ win = dash }) end)
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("nvim_ide", { clear = true }),
  callback = function()
    if vim.env.NVIM_IDE ~= "1" then
      return
    end
    -- 子プロセスへ伝播させない
    vim.env.NVIM_IDE = nil
    vim.g.nvim_ide = true

    -- IDE モード中は :q / :wq を SmartQ / SmartWQ に自動展開
    vim.cmd([[cnoreabbrev <expr> q (getcmdtype()==':' && getcmdline()=='q') ? 'SmartQ' : 'q']])
    vim.cmd([[cnoreabbrev <expr> wq (getcmdtype()==':' && getcmdline()=='wq') ? 'SmartWQ' : 'wq']])

    -- ファイル指定で起動した場合はレイアウトを展開しない
    if vim.fn.argc() > 0 then
      return
    end
    vim.schedule(start_layout)
  end,
})
