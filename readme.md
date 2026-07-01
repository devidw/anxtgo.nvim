# anxtgo.nvim

few years ago i created [anxtgo](https://github.com/devidw/anxtgo)

an app to do personality development through experiential learning

anxtgo.nvim brings the same idea to nvim in a single plain-text file

## installation

- add to your plugin manager
- `require("anxtgo").setup({})` in your config init.lua

## file format

introduces a custom file format to track abstractions and reflections

using marker symbols `{{{ }}}`, using `set foldmethod=marker`

- the title line is just the abstraction name — anxtgo never writes to the file,
  the computed stats are inlaid as a virtual line above each section
- everything after `===` starting with `+` is counted as `+1`, `-` as `-1`. the
  resulting score and the share of positive logs are shown in the inlay
- the positive share is shown with a `✓` marker (e.g. `✓67%`) when there is any
  positivity
- the inlay also shows two streak stats: the current streak (`↑`/`↓` for the
  direction plus the run length, counted from the most recent / first log line)
  and the longest run of consecutive positive logs (`★`)

a section is just a title, notes, and a log:

```
{{{ Some Abstraction Title

Some abstraction notes

===

+ 24-01-01: some reflection log about something, that implemented that abstraction
- 24-01-01: some reflection log about something, that did not implement the abstraction

}}}
...
```

stats are computed asynchronously when the file opens (and again on
`:AnxtgoRank`) and rendered as virtual lines — the buffer text is left
untouched. the `all` row is the total; below it comes one row per month that has
dated logs, newest first:

```
    all   0 ✓50% ↓1 ★1                <- virtual lines, not saved to disk
  24-02  -1   0% ↓1 ★0
  24-01   1 ✓100% ↑1 ★1
{{{ Some Abstraction Title

Some abstraction notes

===

- 24-02-14: some reflection log about something, that did not implement the abstraction
+ 24-01-01: some reflection log about something, that implemented the abstraction

}}}
...
```

each row reads `<label> <score> ✓<positive %> ↑<current streak> ★<longest
positive streak>`, where the label is `all` for the total or `YY-MM` for a
month. months are bucketed from the `YY-MM-DD` date at the start of each log
line; log lines without a date still count toward the total but get no month
row. the stats are anchored just above the `{{{` marker (outside the fold) so
they stay visible whether or not the section is folded.

### special sections

sections named `Meta`, `Archive`, or `X` are kept as-is: they are not scored or
inlaid

## configuration

`setup` accepts an optional `pattern` (passed to the autocmd that renders on
open), defaulting to `{ "*.md" }`. the `AnxtgoStats` highlight group (linked to
`Comment` by default) controls the inlay color.

## usage

- `:AnxtgoRank` to (re)compute scores for the current buffer and refresh the
  inlaid stats
