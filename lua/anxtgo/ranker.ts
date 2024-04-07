class Section {
  content: string
  rank?: number

  constructor(content: string) {
    this.content = content
  }

  computeRank() {
    const logs = this.content.split("===")[1]
    this.rank = logs
      .split("\n")
      .map((a) => a.trim())
      .filter((a) => a.length > 0 && ["-", "+"].includes(a[0]))
      .reduce((previousValue, currentValue) => {
        if (currentValue.startsWith("-")) {
          return previousValue - 1
        } else if (currentValue.startsWith("+")) {
          return previousValue + 1
        } else {
          throw new Error("bad start of line " + currentValue)
        }
      }, 0)
  }

  toString() {
    const lines = this.content.split("\n")
    const title = lines.shift()
    const newTitle = `${title?.split(" | ")[0]} | ${this.rank}`
    return `{{{${newTitle}\n\n${lines.join("\n").trim()}\n\n}}}`
  }
}

function getSections(input: string): Section[] {
  const all = input.matchAll(/\{{3}([^\{\}]+)\}{3}/g)

  const allArr = [...all].map((a) => {
    return a[1]
  })

  return allArr.map((a) => new Section(a))
}

const FILE_PATH = Deno.args[0]
const BACKUP_PATH = Deno.args[1]

// console.log(FILE_PATH)

const contents = Deno.readTextFileSync(FILE_PATH)

// console.log(contents)

const sections = getSections(contents)

// console.log(sections)

sections.forEach((a) => a.computeRank())

// console.log(sections.map((a) => a.rank))

sections.sort((a, b) => a.rank! - b.rank!)

const out = sections.map((a) => a.toString()).join("\n\n")

// console.log(out)

Deno.copyFileSync(FILE_PATH, BACKUP_PATH)

Deno.writeTextFileSync(FILE_PATH, out)
