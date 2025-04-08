#import "../consts.typ": *

#let set-raw-style(info, body) = {
  show raw: set block(breakable: true)

  show raw: it => {
    set text(font: info.at(all-keys.code-font))
    it
  }

  show raw.where(block: true): it => {
    set text(size: 1em)
    set par(justify: false)
    it
  }

  show raw.where(block: false): it => {
    set text(size: 0.9em, fill: info.at(all-keys.inline-code-color))
    h(0.3em)
    box(fill: luma(240), inset: (top: 0.15em, bottom: 0.15em), outset: (top: 0.15em, bottom: 0.15em), radius: 0.2em)[
      #h(0.2em) #it #h(0.2em)
    ]
    h(0.3em)
  }

  body
}