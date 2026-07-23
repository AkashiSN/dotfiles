-- 端末バッファ内の URL を下線ハイライトし、カーソル下の URL を `gx` で開く。
-- nvim 既定の `gx` はファイルバッファでは効くが端末バッファでは URL を拾えないため、
-- `:terminal`（herdr ペインで動かす claude/codex 等を含む）の出力に対して補う。
-- TermOpen で各端末バッファへ付与し、出力が伸びるたびに新規行ぶんの URL を拾い直す。

local M = {}

local URL_NS = vim.api.nvim_create_namespace("nvim_terminal_urls")
local URL_PATTERN = "https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+"
local URL_HL = "NvimTerminalUrl"
local url_pending = {}

vim.api.nvim_set_hl(0, URL_HL, { underline = true, default = true })

-- URL の末尾に付いた閉じ括弧・句読点を削る。対応の取れない `)` `]` と、
-- 文末に紛れ込みがちな記号を落とす（`https://example.com/foo).` → `https://example.com/foo`）。
local function trim_url(url)
  while #url > 0 do
    local last = url:sub(-1)
    if last == ")" then
      local opens = select(2, url:gsub("%(", ""))
      local closes = select(2, url:gsub("%)", ""))
      if closes <= opens then
        break
      end
    elseif last == "]" then
      local opens = select(2, url:gsub("%[", ""))
      local closes = select(2, url:gsub("%]", ""))
      if closes <= opens then
        break
      end
    elseif not last:match("[.,;:!?>}]") then
      break
    end
    url = url:sub(1, -2)
  end
  return url
end

-- [firstline, lastline) の行を走査して URL に extmark（下線）を張り直す。
local function refresh_url_links(buf, firstline, lastline)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count == 0 then
    return
  end

  local first = math.max(0, math.min(firstline, line_count - 1))
  local last = math.max(first + 1, math.min(lastline, line_count))
  pcall(vim.api.nvim_buf_clear_namespace, buf, URL_NS, first, last)

  local lines = vim.api.nvim_buf_get_lines(buf, first, last, false)
  for i, line in ipairs(lines) do
    local row = first + i - 1
    local pos = 1
    while true do
      local start_col, end_col = line:find(URL_PATTERN, pos)
      if not start_col then
        break
      end

      local raw = line:sub(start_col, end_col)
      local url = trim_url(raw)
      if url ~= "" then
        pcall(vim.api.nvim_buf_set_extmark, buf, URL_NS, row, start_col - 1, {
          end_row = row,
          end_col = start_col - 1 + #url,
          hl_group = URL_HL,
          url = url,
          priority = 200,
          invalidate = true,
        })
      end
      pos = end_col + 1
    end
  end
end

-- on_lines は fast-context で発火しカーソル/描画 API を直接呼べないため、対象範囲を
-- 覚えて vim.schedule 経由で 1 ティック 1 回にまとめて refresh する。
local function schedule_url_links(buf, firstline, lastline)
  local first = math.max(0, firstline - 1)
  local last = lastline + 1
  local pending = url_pending[buf]
  if pending then
    pending.first = math.min(pending.first, first)
    pending.last = math.max(pending.last, last)
    return
  end

  url_pending[buf] = { first = first, last = last }
  vim.schedule(function()
    local range = url_pending[buf]
    url_pending[buf] = nil
    if range then
      refresh_url_links(buf, range.first, range.last)
    end
  end)
end

-- カーソル位置にかかる URL を返す（無ければ nil）。
local function url_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local pos = 1
  while true do
    local start_col, end_col = line:find(URL_PATTERN, pos)
    if not start_col then
      return nil
    end

    local raw = line:sub(start_col, end_col)
    local url = trim_url(raw)
    local mark_start = start_col - 1
    local mark_end = mark_start + #url
    if mark_start <= col and col < mark_end then
      return url
    end
    pos = end_col + 1
  end
end

local function open_url_under_cursor()
  local url = url_under_cursor()
  if not url then
    return false
  end
  local ok, err = pcall(vim.ui.open, url)
  if not ok then
    vim.notify("URL を開けませんでした: " .. tostring(err), vim.log.levels.WARN)
  end
  return true
end

-- 端末バッファに URL リンク機能を付ける: (a) バッファローカル gx、(b) 初回ハイライト、
-- (c) 以後の出力を on_lines で拾い直す。gx はカーソル下 URL があれば開き、無ければ標準 gx。
local function enable_url_links(buf)
  vim.keymap.set("n", "gx", function()
    if not open_url_under_cursor() then
      vim.cmd.normal({ "gx", bang = true })
    end
  end, { buffer = buf, desc = "Open URL under cursor" })
  refresh_url_links(buf, 0, vim.api.nvim_buf_line_count(buf))
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, _, firstline, _, lastline)
      schedule_url_links(b, firstline, lastline)
      return false -- false=アタッチ維持
    end,
  })
end

vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("nvim_terminal_urls", { clear = true }),
  callback = function(ev)
    enable_url_links(ev.buf)
  end,
})

return M
