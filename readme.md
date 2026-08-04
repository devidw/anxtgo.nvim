# anxtgo.nvim

few years ago i created [anxtgo](https://github.com/devidw/anxtgo)

an app to do personality development through experiential learning

anxtgo.nvim brings the same idea to nvim in a single plain-text file

## installation

- add to your plugin manager
- `require("anxtgo").setup({})` in your config init.lua

## file format

plain markdown, structured by headings

- each abstraction is an `##` section, the heading is just its name — anxtgo
  never writes to the title line, the computed stats are inlaid as virtual lines
  below it
- inside a section, logs live under `### YY-MM` month headings. those headings
  are managed: `:AnxtgoRank` creates the ones that are missing, moves logs to
  the month their date says they belong to, and drops the ones left empty
- a log line starts with `+` (counted as `+1`), `-` (`-1`), or `*` (`0`). it
  counts as a log when it carries a `YY-MM-DD` date anywhere in the line, or
  when it sits under a month heading — so an ordinary `- bullet` up in the notes
  stays prose
- `*` marks a day that was excluded or did not apply. it is a real entry and is
  grouped by month like the others, but it is transparent to every stat: it
  scores nothing, it is left out of the positive share, and it neither extends
  nor breaks a streak — a `+ * +` run is a streak of two
- an entry can span several lines: everything indented below its marker line
  belongs to it and is refiled along with it. indentation wins over the marker,
  so an indented `- sub point` is part of the entry above it, not a log of its
  own. blank lines inside an entry are kept as long as indented content follows
- undated logs are collected under a `### ?` heading at the end of the section.
  they count toward the total but get no month row
- the positive share is shown with a `✓` marker (e.g. `✓67%`) when there is any
  positivity, followed by the raw totals (`+n` positive, `-n` negative logs)
- the inlay also shows two streak stats: the current streak (`↑`/`↓` for the
  direction plus the run length, counted from the most recent / first log line)
  and the longest run of consecutive positive logs (`★`)

a section is just a heading, notes, and the months:

```markdown
## Some Abstraction Title

Some abstraction notes

### 24-02

- 24-02-14: some reflection log about something, that did not implement the abstraction
  more detail about that same day, indented so it stays part of the entry
  - a sub point of it
* 24-02-13: travelling, the abstraction did not apply

### 24-01

+ 24-01-01: some reflection log about something, that implemented that abstraction
```

anything you write outside a `##` section (a `#` document title, frontmatter) is
left untouched.

## stats

stats are computed asynchronously when the file opens (and again on
`:AnxtgoRank`) and rendered as virtual lines — never saved to disk. the `all`
row is the total; below it comes one row per month that has dated logs, newest
first:

```
## Some Abstraction Title
     all   ✓50%  +1  -1  *1  ★1    <- virtual lines, not saved to disk
   24-02     0%  +0  -1  *1  ★0  ↓1
   24-01  ✓100%  +1  -0  *0  ★1

Some abstraction notes

### 24-02
...
```

each row reads `<label> ✓<positive %> +<positives> -<negatives> *<excluded>
★<record>`, where the label is `all` for the total or `YY-MM` for a month, and
the record (`★`) is the longest run of consecutive positive logs in that scope.
the `*` column only appears when the section has excluded days at all. the
current streak (`↑`/`↓` plus its length) is momentum-of-now, so it is shown on
exactly one row — the newest month (or the `all` row when there are no dated
logs). within a section the label, %, total and record columns are each padded
to the widest value in the group and separated by two spaces, so they line up.

the stats are anchored below the `##` heading, i.e. inside the section, so
folding all `##` sections leaves nothing on screen but the headings themselves.

### special sections

sections named `Meta`, `Archive`, or `X` are kept as-is: they are not scored, not
inlaid, and their logs are never refiled

## configuration

`setup` accepts an optional `pattern` (passed to the autocmd that renders on
open), defaulting to `{ "*.md" }`. the `AnxtgoStats` highlight group (linked to
`Comment` by default) controls the inlay color.

## usage

- `:AnxtgoRank` to refile the logs under their month headings, recompute the
  scores for the current buffer, and refresh the inlaid stats
- opening a file only renders the stats — the buffer text is rewritten by
  `:AnxtgoRank` only
