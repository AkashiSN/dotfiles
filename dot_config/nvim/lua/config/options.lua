-- 基本オプション
local opt = vim.opt

opt.number = true
opt.relativenumber = false
opt.signcolumn = "yes"
opt.cursorline = true
opt.termguicolors = true
opt.mouse = "a"
opt.scrolloff = 8
opt.wrap = false

-- インデント（プロジェクト規約: tab=4, spaces）
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.smartindent = true

-- 検索
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- ファイル
opt.undofile = true
opt.swapfile = false
opt.fileencoding = "utf-8"

-- 分割の向き（VSCode 感覚）
opt.splitright = true
opt.splitbelow = true

-- diff 表示（diffview / vimdiff 共通）
-- 既定の fillchars は diff:- で、片側にしか行が無い「埋め草行」が
-- ハイフン(やスラッシュ)の壁になり見にくい。埋め草行の文字を空白にして、
-- catppuccin の DiffDelete が持つ赤系背景だけが残るようにする。
opt.fillchars:append({ diff = " " })
-- linematch: 変更行どうしを賢く対応付けし、行内の差分だけを色付け
-- (ブロック丸ごとが差分扱いになりにくく、行単位の違いが見やすい)。
opt.diffopt:append("linematch:60")

-- 補完・UI
opt.completeopt = "menu,menuone,noselect"
opt.updatetime = 250
opt.timeoutlen = 400
opt.winminwidth = 5

-- クリップボード連携の決定:
--   * mac ローカル                … pbcopy/pbpaste
--   * X11/Wayland のある Linux     … wl-copy / xclip / xsel
--     （いずれも nvim が自動検出して使う）
--   * OS ツールが無い環境          … OSC52 で端末経由コピー
--     SSH 越し・docker exec で入ったコンテナなど。ghostty/tmux が OSC52 を
--     中継するので X11/Wayland 不要。これが無いと「clipboard provider not
--     found」警告になりヤンクが端末クリップボードへ届かない。
opt.clipboard = "unnamedplus"
local function has(bin)
  return vim.fn.executable(bin) == 1
end
local has_native_clipboard = has("pbcopy") or has("wl-copy") or has("xclip") or has("xsel")
if not has_native_clipboard then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok then
    vim.g.clipboard = {
      name = "OSC52",
      copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
      paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
    }
  end
end

-- URL/ファイルを開くとき $BROWSER を優先する。
-- 標準の vim.ui.open は mac:open / Linux:xdg-open を使い $BROWSER を見ないため、
-- SSH 先（$BROWSER=portfwd-open でローカル mac のブラウザへ転送）だと URL を開けない。
-- BROWSER が実行可能ならそれを使い、無ければ標準動作へフォールバックする
-- （ローカル mac では BROWSER 未設定なので従来どおり open が使われる）。
do
  local builtin_open = vim.ui.open
  vim.ui.open = function(uri)
    local browser = vim.env.BROWSER
    if browser and browser ~= "" and vim.fn.executable(browser) == 1 then
      local ok, obj = pcall(vim.system, { browser, uri }, { detach = true })
      if ok then
        return obj, nil
      end
      return nil, "vim.ui.open: failed to run " .. browser
    end
    return builtin_open(uri)
  end
end

-- 診断表示
vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = "rounded" },
})
