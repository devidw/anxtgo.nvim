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

- the title line holds the abstraction name after a `|`; everything before the
  `|` is managed by anxtgo (the score, the positive share, and streak stats)
- everything after `===` starting with `+` is counted as `+1`, `-` as `-1`. the
  resulting score and the share of positive logs are placed in the title line
- the positive share is shown with a `✓` marker (e.g. `✓67%`) when there is any
  positivity
- the title also shows two streak stats: the current streak (`↑`/`↓` for the
  direction plus the run length, counted from the most recent / first log line)
  and the longest run of consecutive positive logs (`★`)
- the sections are reordered by score, from lowest to greatest

you can start a section with just a title, anxtgo fills in the managed prefix on
the next rank:

```
{{{ Some Abstraction Title

Some abstraction notes

===

+ 24-01-01: some reflection log about something, that implemented that abstraction
- 24-01-01: some reflection log about something, that did not implement the abstraction

}}}
...
```

after `:AnxtgoRank` the title line becomes
`<score> ✓<positive %> ↑<current streak> ★<longest positive streak> | <name>`:

```
{{{   0 ✓50% ↑1 ★1 | Some Abstraction Title

Some abstraction notes

===

+ 24-01-01: some reflection log about something, that implemented that abstraction
- 24-01-01: some reflection log about something, that did not implement the abstraction

}}}
...
```

### special sections

sections named `Meta`, `Archive`, or `X` are kept as-is: they are not scored or
reordered, and they always sort to the top of the file

## usage

- `:AnxtgoPositive` to insert `+ YY-MM-DD:`
- `:AnxtgoNegative` to insert `- YY-MM-DD:`
- `:AnxtgoRank` to process the current buffer and calcualte scores and reorder
  abstractions based on scores
