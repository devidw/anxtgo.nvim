# anxtgo.nvim

few years ago i created [anxtgo](https://github.com/devidw/anxtgo)

an app to do personality development through experiential learning

anxtgo.nvim brings the same idea to nvim in a single plain-text file

## installation

- requires deno to be available
- add to your plugin manager
- `require("anxtgo").setup({})` in your config init.lua

## file format

introduces a custom file format to track abstractions and reflections

using marker symbols `{{{ }}}`, using `set foldmethod=marker`

- everything after `|` in the title line is managed by anxtgo
- everything after `===` starting with `+` is counted as `+1`, `-` as `-1`, the
  resulting score is placed in the title line
- also the sections will be reorderd based on the score, from lowest to greatest

```
{{{ Some Abstraction Title | 0

Some abstraction notes

===

+ 24-01-01: some reflection log about something, that implemented that abstraction
- 24-01-01: some reflection log about something, that did not implemented the abstraction

}}}
...
```

## usage

- `:AnxtgoPositive` to insert `+ YY-MM-DD:`
- `:AnxtgoNegative` to insert `- YY-MM-DD:`
- `:AnxtgoRank` to process the current buffer and calcualte scores and reorder
  abstractions based on scores
