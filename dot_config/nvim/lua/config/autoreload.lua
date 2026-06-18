-- 外部ファイル変更の自動同期 + 保存時コンフリクト解決
-- 挙動A: 未編集バッファは外部変更を検知して静かに自動リロード
-- 挙動B: 編集中バッファは保存時に検知して .bak 退避 + 3択（Task 2 で実装）

local group = vim.api.nvim_create_augroup("external_sync", { clear = true })

-- 外部変更を検知したら自動でバッファに反映する
vim.opt.autoread = true

-- ファイルの mtime(ナノ秒)を取得（存在しなければ nil）
local function disk_mtime(path)
  local st = vim.uv.fs_stat(path)
  return st and st.mtime.sec * 1000000000 + st.mtime.nsec or nil
end

-- バッファに「最後に同期した mtime」を記録する
local function record_mtime(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if path ~= "" then
    vim.b[buf].synced_mtime = disk_mtime(path)
  end
end

-- バックアップ先パス: <元パス>.<timestamp>.bak（同じディレクトリ）
local function backup_path(path)
  return path .. "." .. os.date("%Y%m%d-%H%M%S") .. ".bak"
end

-- 読込・書込のたびに同期 mtime を更新する
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "FileChangedShellPost" }, {
  group = group,
  callback = function(ev)
    record_mtime(ev.buf)
  end,
})

-- nvim は常時監視しないので、フォーカス・バッファ移動・無操作で :checktime を発火する
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermLeave" }, {
  group = group,
  callback = function()
    -- コマンドラインモード中など checktime が使えない状況では何もしない
    if vim.fn.mode() ~= "c" then
      pcall(vim.cmd.checktime)
    end
  end,
})

-- 外部変更検知時のハンドラ: 未編集なら静かにリロード（挙動A）、編集中は記録（挙動B）
vim.api.nvim_create_autocmd("FileChangedShell", {
  group = group,
  callback = function(ev)
    if not vim.bo[ev.buf].modified then
      vim.v.fcs_choice = "reload" -- 挙動A: 静かにリロード
      return
    end
    -- 挙動B: 編集中はエディタの変更を保持し、保存時に確認する
    vim.v.fcs_choice = ""
    if not vim.b[ev.buf].external_conflict then
      vim.b[ev.buf].external_conflict = true
      vim.notify("外部で変更されました（保存時に確認します）", vim.log.levels.WARN)
    end
  end,
})

-- バッファ内容を実際にディスクへ書き込む（BufWriteCmd 配下の手動 write）
local function do_write(buf, path)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- 末尾改行など nvim 標準の write 挙動に寄せるため writefile を使う
  vim.fn.writefile(lines, path)
  vim.bo[buf].modified = false
  vim.b[buf].external_conflict = nil
  record_mtime(buf)
end

-- 3択コンフリクト解決
local function resolve_conflict(buf, path)
  local choice = vim.fn.confirm(
    "「" .. vim.fn.fnamemodify(path, ":t") .. "」は外部で変更されています。どうしますか？",
    "&自分の版で上書き\n&外部版を取り込む\n&diffを開く",
    1
  )
  if choice == 1 then
    -- 失われる外部版を退避してから自分の版で上書き
    local bak = backup_path(path)
    vim.fn.writefile(vim.fn.readfile(path), bak)
    do_write(buf, path)
    vim.notify("自分の版で上書きしました（外部版: " .. vim.fn.fnamemodify(bak, ":t") .. "）", vim.log.levels.INFO)
  elseif choice == 2 then
    -- 失われる自分の編集を退避してから外部版を取り込む
    local bak = backup_path(path)
    vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), bak)
    vim.bo[buf].modified = false
    vim.b[buf].external_conflict = nil
    vim.cmd.edit({ bang = true }) -- ディスク（外部版）で再読込
    vim.notify("外部版を取り込みました（自分の編集: " .. vim.fn.fnamemodify(bak, ":t") .. "）", vim.log.levels.INFO)
  elseif choice == 3 then
    -- 外部版を .bak に退避し、それと縦分割で diff（書き込みはしない）
    local bak = backup_path(path)
    vim.fn.writefile(vim.fn.readfile(path), bak)
    vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(bak))
    vim.notify("外部版を " .. vim.fn.fnamemodify(bak, ":t") .. " として diff 表示。マージ後に再度 :w してください", vim.log.levels.INFO)
  else
    vim.notify("保存をキャンセルしました", vim.log.levels.INFO)
  end
end

-- 保存を横取りし、外部変更があれば解決フローへ
vim.api.nvim_create_autocmd("BufWriteCmd", {
  group = group,
  callback = function(ev)
    local path = vim.api.nvim_buf_get_name(ev.buf)
    if path == "" then
      return
    end
    local synced = vim.b[ev.buf].synced_mtime
    local current = disk_mtime(path)
    -- 同期後にディスクが変わっている、または既にコンフリクト記録済み
    if vim.b[ev.buf].external_conflict or (synced and current and current ~= synced) then
      resolve_conflict(ev.buf, path)
    else
      do_write(ev.buf, path)
    end
  end,
})
