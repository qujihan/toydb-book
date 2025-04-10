#import "@preview/lovelace:0.3.0": *
#import "../book-template/book.typ":*

#let figure-kind-query-sql = "figure-kind-query-sql"
// 必须是这个
#let figure-kind-algorithm = "algorithm"

#let sql-code-show-stype(body) = {
  show figure.where(kind: figure-kind-query-sql):it => {
    set figure.caption(position: top)
    show figure.caption: it => {
      box(width: 80%)[
        #set align(center + horizon)
        #set text(font: "Maple Mono NF", size: 11pt)
        #grid(
          rows: 1em,
          columns: (2.5fr, 1fr, 2.5fr),
          line(stroke: black.lighten(50%), length: 100%),
          it,
          line(stroke: black.lighten(50%), length: 100%),
        )
      ]
    }
    block(breakable: false)[
      #set par(spacing: 0.6em)
      #it
      #box(width: 80%, inset: (top: 0em))[
        #line(stroke: black.lighten(50%), length: 100%)
      ]
    ]
  }
  body
}

#let sql-code(code) = {
  figure(code, supplement: "Query", numbering: "1", kind: figure-kind-query-sql, caption: "")
}

#let algorithm-code-show-stype(body) = {
  show figure.where(kind: figure-kind-algorithm):it => {
    show "function": it => strong(it)
    show "for": it => strong(it)
    show "do": it => strong(it)
    show "if": it => strong(it)
    show "then": it => strong(it)
    show "else": it => strong(it)
    show "while": it => strong(it)
    show "return": it => strong(it)
    it
  }
  body
}
#let algorithm-code(title, code) = {
  figure(
    kind: figure-kind-algorithm,
    supplement: [算法],
    pseudocode-list(booktabs: true, line-numbering: "1:", numbered-title: [#title], booktabs-stroke: 1pt + black, code),
  )
}