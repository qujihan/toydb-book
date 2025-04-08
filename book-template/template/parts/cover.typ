#let display-cover(book-title, author) = [
  #set page(paper: "a4", margin: (x: 0pt, y: 0pt), header: none, footer: none, background: none, fill: white)

  #align(center + horizon, block(width: 100%, height: 30%, fill: gray.transparentize(40%))[
    #text(size: 2em, weight: "bold")[#book-title]
    #v(3em)
    #text(size: 1.5em, weight: "bold")[#author]
    #v(1em)
  ])
]