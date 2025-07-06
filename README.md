# Extmarks

Why not use regular marks?

- Extmarks endure changes to the buffer (seems to be the case for regular marks as well?)
- Valid cross-file (without being uppercase). Yes, could do a remap.
- Can assign numbers and have them persist without getting shifted
- Restore view as well as cursor position (since 0.11 built-in to nvim with `jumpoptions+=view`)
- View marks file, also through fzf (could implement on top of regular marks)

Of course, these may not be sufficient reasons,
since a lot can be achieved with remaps and building on top of regular marks,
which would yield easier integration with other plugins (fzf, which-key, mini-map?).

Why not harpoon:

- Can have multiple marks per file

Other alternatives:

- harpoon2
- crusj/bookmarks.nvim
- vim-bookmarks
- marks.nvim
- nvim-project-marks
- LintaoAmons/bookmarks.nvim
- tomasky/bookmarks.nvim
- arrow.nvim
