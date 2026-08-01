# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`emarks.nvim` is a Neovim plugin that implements persistent, numbered/lettered marks backed by
extmarks instead of Vim's built-in marks. Extmarks survive buffer edits and can be restored
(position + view) across sessions, unlike regular marks which shift as the file is edited outside
the current session.

## Development

There is no build step, test suite, linter config beyond StyLua, or CI in this repo.

- Formatting: `stylua.toml` sets 2-space indent, 120 column width. Run `stylua .` if stylua is
  installed; there's no npm/make wrapper for it.
- To manually exercise changes, symlink or point a Neovim plugin manager (this repo lives under
  `~/.local/share/nvim/lazy/`, i.e. it's already loaded via lazy.nvim) at this directory and
  `:Lazy reload emarks.nvim`, or just restart Neovim.
- There are no automated tests. Verify behavior by hand in a running Neovim instance (set marks,
  restart Neovim, confirm they reload; check the fzf-lua picker and which-key integration if those
  plugins are installed).

## Architecture

- `lua/emarks/init.lua` — plugin entrypoint. `setup()` wires config, creates the `aug_emarks`
  augroup, and registers a `VimLeavePre` autocmd that autosaves marks (skippable via
  `save_empty`/`pre_save` options).
- `lua/emarks/config.lua` — options (`dir`: where per-project mark files are stored, `save_empty`,
  `pre_save`).
- `lua/emarks/core.lua` — all the actual logic; everything else in the plugin is a thin
  integration layer on top of it. Read this file first when working on core behavior. Its layout
  (see the boxed section headers in the file) is:
  - **Core (in-memory)**: `extmarks` is a `label -> {bufnr_or_filename, extmark_id_or_pos}` table
    keyed by single-character labels (`1-9`, `A-Z`, `a-z`, stored in `M.labelS`). A parallel
    `views` table stores `winsaveview()` output per label so cursor *and* scroll position can be
    restored. `M.extmark_locations()` resolves the live table into `{filename, {line, col}}` pairs
    (1-based), converting bufnr -> filename and extmark id -> current position on the fly. This
    function is a de facto external API — third-party integrations (e.g. a `mini.map` fork's marks
    integration) call `require("emarks.core").extmark_locations()` directly — so its name and
    return shape need to stay stable even as other internals change.
  - **Mappings**: sets up `m<label>` to mark, `'<label>`/`` `<label> `` to jump (the backtick
    variant skips view restoration, mirroring vim's own `'`/`` ` `` distinction), `dm` to clear the
    mark under cursor, `mm` to auto-assign the lowest free label (`get_lowest_available_label`),
    and `<M-N>`/`<M-P>` to cycle through marks in label-sorted order (`goto_mark_cyclical`).
  - **Read/Write storage**: one marks file per project, derived from `getcwd()` (path separators
    escaped to `%`) under `Config.options.dir`, e.g. `~/.local/state/nvim/emarks/%path%to%project.emarks`.
    Saved with `vim.inspect`/`load()` — the file is literal Lua source (a table with `extmarks` and
    `views` keys), not JSON. `M.reload_for_buffer()` re-creates real extmarks for a buffer just
    opened, since only extmark *ids* (not positions) round-trip through storage — positions are
    resolved live from the extmark id while the buffer is loaded.
  - **Facilitate view/edit of storage file**: `<leader>'` (`M.show()`) opens the raw `.emarks` file
    for direct editing; saving it triggers `M.load()` to re-parse. Opening it also appends the
    current line contents as trailing `-- comments` per mark for readability (these comments are
    regenerated on each entry into the buffer and are not treated as data), and binds a
    buffer-local `<CR>` to jump to the mark on the current line.
- `lua/emarks/fzf-lua-hook.lua` — optional integration, no-ops (via `pcall(require, ...)`) if
  fzf-lua isn't installed or running headless. Adds a `''` mapping that opens an fzf-lua picker
  over `emarks.extmark_locations()`, with a custom previewer subclassing fzf-lua's builtin marks
  previewer.
- `lua/emarks/which-key-hook.lua` — optional integration, no-ops if which-key (or its internal
  `which-key.plugins.marks` module) isn't present. Monkey-patches `wk.run` (copy-pasted from
  which-key's own marks plugin) so the which-key marks popup shows emarks merged in alongside
  built-in marks, filtering out any built-in mark whose key collides with an emark label.
- Labels are single characters. `1-9`, then `A-Z`, then `a-z` for the full label set (`M.labelS`);
  `get_lowest_available_label` (used by `mm`) only cycles through `1-9` + lowercase `qwertyuipasdfghjkl`.
