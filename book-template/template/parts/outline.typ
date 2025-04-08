#let display-outline(show-depth) = [
  #set page(header: none, footer: none, background: none)
  #set heading(numbering: none, outlined: false)

  #show outline.entry.where(level: 1): it => {
    text(size: 1em, weight: "semibold", it)
  }

  #show outline.entry.where(level: 2): it => {
    text(size: 1em, weight: "medium", it)
  }

  #show outline.entry.where(level: 3): it => {
    text(size: 1em, weight: "regular", it)
  }

  #set align(center)
  #outline(indent: auto, depth: show-depth, title: "目录")
]