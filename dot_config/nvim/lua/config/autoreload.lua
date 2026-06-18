-- 外部ファイル変更の自動同期 + 保存時コンフリクト解決
-- 挙動A: 未編集バッファは外部変更を検知して静かに自動リロード
-- 挙動B: 編集中バッファは保存時に検知して .bak 退避 + 3択

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

-- バックアップ先パス: <元パス>.<timestamp>.bak（同じディレクトリ）。
-- 同一秒に複数回退避しても前のバックアップを潰さないよう、衝突時は連番を付ける。
local function backup_path(path)
  local base = path .. "." .. os.date("%Y%m%d-%H%M%S") .. ".bak"
  local candidate = base
  local n = 1
  while vim.uv.fs_stat(candidate) do
    candidate = base .. "." .. n
    n = n + 1
  end
  return candidate
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

-- 外部変更検知時のハンドラ
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

-- バッファ内容を nvim 標準の write で書き込む（eol/fileformat/encoding を正しく扱う）。
-- noautocmd で BufWriteCmd の再帰を防ぎ、write! で「外部変更後」チェックを越える。
local function do_write(buf)
  local ok, err = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("noautocmd write!")
    end)
  end)
  if not ok then
    vim.notify("書き込みに失敗しました: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  vim.bo[buf].modified = false
  vim.b[buf].external_conflict = nil
  record_mtime(buf)
  return true
end

-- ディスク上の外部版をそのまま .bak へコピー（バイト単位、eol を変えない）
local function backup_disk(path, bak)
  local ok = vim.uv.fs_copyfile(path, bak)
  if not ok then
    vim.notify("バックアップに失敗したため中止しました: " .. path, vim.log.levels.ERROR)
    return false
  end
  return true
end

-- バッファの未保存編集を .bak へ書き出す（nvim 標準 write）
local function backup_buffer(buf, bak)
  local ok = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("noautocmd write! " .. vim.fn.fnameescape(bak))
    end)
  end)
  if not ok then
    vim.notify("バックアップに失敗したため中止しました: " .. bak, vim.log.levels.ERROR)
    return false
  end
  return true
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
    if not backup_disk(path, bak) then
      return
    end
    if do_write(buf) then
      vim.notify("自分の版で上書きしました（外部版: " .. vim.fn.fnamemodify(bak, ":t") .. "）", vim.log.levels.INFO)
    end
  elseif choice == 2 then
    -- 失われる自分の編集を退避してから外部版を取り込む
    local bak = backup_path(path)
    if not backup_buffer(buf, bak) then
      return
    end
    vim.bo[buf].modified = false
    vim.b[buf].external_conflict = nil
    vim.api.nvim_buf_call(buf, function()
      vim.cmd.edit({ bang = true }) -- ディスク（外部版）で再読込
    end)
    vim.notify("外部版を取り込みました（自分の編集: " .. vim.fn.fnamemodify(bak, ":t") .. "）", vim.log.levels.INFO)
  elseif choice == 3 then
    -- 外部版を .bak に退避し、それと縦分割で diff（書き込みはしない）。
    -- コンフリクトを解消済み扱いにし、マージ後の :w は通常保存（自分の版で上書き）になる。
    local bak = backup_path(path)
    if not backup_disk(path, bak) then
      return
    end
    vim.b[buf].external_conflict = nil
    vim.b[buf].synced_mtime = disk_mtime(path)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(bak))
    end)
    vim.notify("外部版を " .. vim.fn.fnamemodify(bak, ":t") .. " として diff 表示。マージ後に再度 :w すると自分の版で保存されます", vim.log.levels.INFO)
  else
    vim.notify("保存をキャンセルしました", vim.log.levels.INFO)
  end
end

-- 保存を横取りし、外部変更があれば解決フローへ
vim.api.nvim_create_autocmd("BufWriteCmd", {
  group = group,
  callback = function(ev)
    local buf = ev.buf
    local path = vim.api.nvim_buf_get_name(buf)
    local target = ev.match -- 書き込み先（:w other.txt なら other.txt）
    -- バッファ名は symlink 解決済み・ev.match は未解決のことがあるため、
    -- 両辺を resolve+絶対パス化してから比較する（/tmp 等 symlink 配下の誤判定を防ぐ）。
    local function abspath(p)
      return vim.fn.resolve(vim.fn.fnamemodify(p, ":p"))
    end
    local same = path ~= "" and target ~= "" and abspath(target) == abspath(path)
    if not same then
      -- 別名保存・無名バッファ等はコンフリクト処理の対象外。標準 write に委ねる。
      local ok, err = pcall(function()
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("noautocmd write " .. (target ~= "" and vim.fn.fnameescape(target) or ""))
        end)
      end)
      if not ok then
        vim.notify("書き込みに失敗しました: " .. tostring(err), vim.log.levels.ERROR)
      end
      return
    end
    local synced = vim.b[buf].synced_mtime
    local current = disk_mtime(path)
    -- 同期後にディスクが変わっている、または既にコンフリクト記録済み
    if vim.b[buf].external_conflict or (synced and current and current ~= synced) then
      resolve_conflict(buf, path)
    else
      do_write(buf)
    end
  end,
})
