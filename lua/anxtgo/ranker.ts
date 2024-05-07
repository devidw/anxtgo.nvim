/**
 * highly unoptimized implementation
 */
class Section {
  content: string
  rank?: number
  posCount = 0
  negCount = 0

  constructor(content: string) {
    this.content = content
  }

  get name() {
    const lines = this.content.split("\n")
    const title = lines.shift()
    if (!title) return
    return title.split(" | ")[0].trim()
  }

  get isSpecial() {
    return this.name === "X" || this.name === "Meta"
  }

  get count() {
    return this.negCount + this.posCount
  }

  get posShare() {
    return this.posCount / this.count
  }

  get negShare() {
    return this.negCount / this.count
  }

  computeRank() {
    const logs = this.content.split("===")[1]

    logs
      .split("\n")
      .map((a) => a.trim())
      .filter((a) => a.length > 0 && ["-", "+"].includes(a[0]))
      .map((currentValue) => {
        if (currentValue.startsWith("-")) {
          this.negCount++
        } else if (currentValue.startsWith("+")) {
          this.posCount++
        } else {
          throw new Error("bad start of line " + currentValue)
        }
      }, 0)

    this.rank = this.posCount - this.negCount
  }

  toString() {
    const lines = this.content.split("\n")
    lines.shift()
    const newTitle = this.isSpecial
      ? this.name
      : `${this.name} | ${this.rank} ${Math.round(this.posShare * 100)}%`
    return `{{{ ${newTitle}\n\n${lines.join("\n").trim()}\n\n}}}`
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

const specials: Section[] = []
const ranked: Section[] = []

sections.forEach((a) => {
  if (a.isSpecial) {
    specials.push(a)
  } else {
    ranked.push(a)
  }
})

ranked.forEach((a) => a.computeRank())

// console.log(sections.map((a) => a.rank))

ranked.sort((a, b) => a.rank! - b.rank!)

const out = [...specials, ...ranked].map((a) => a.toString()).join("\n\n")

// console.log(out)

Deno.copyFileSync(FILE_PATH, BACKUP_PATH)

Deno.writeTextFileSync(FILE_PATH, out)
