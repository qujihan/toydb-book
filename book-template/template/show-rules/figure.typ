#import "../consts.typ": *

#let figure-kind-code = "figure-kind-code"
#let figure-kind-pic = "figure-kind-pic"
#let figure-kind-tbl = "figure-kind-tbl"

#let figure-env-set(info, body) = {
  show figure.where(kind: figure-kind-tbl): set figure.caption(position: top)
  show figure.caption: it => box(box(align(left, it)), width: 80%)

  let count-step(kind) = {
    let chapter-num = counter(heading.where(level: 1)).display()
    counter(kind + str(chapter-num)).step()
  }

  show figure: it => {
    set block(breakable: true)
    if it.kind == figure-kind-code {
      count-step(figure-kind-code)
    } else if it.kind == figure-kind-pic {
      count-step(figure-kind-pic)
    } else if it.kind == figure-kind-tbl {
      count-step(figure-kind-tbl)
    }
    it
  }

  body
}

#let tbl-numering(_) = {
  let chapter-num = counter(heading.where(level: 1)).display()
  let type-num = counter(figure-kind-tbl + chapter-num).display()
  numbering("1", counter(heading.where(level: 1)).get().first()) + "-" + str(int(type-num) + 1)
}

#let pic-numering(_) = {
  let chapter-num = counter(heading.where(level: 1)).display()
  let type-num = counter(figure-kind-pic + chapter-num).display()
  numbering("1", counter(heading.where(level: 1)).get().first()) + "-" + str(int(type-num) + 1)
}

#let code-numering(_) = {
  let chapter-num = counter(heading.where(level: 1)).display()
  let type-num = counter(figure-kind-code + chapter-num).display()
  numbering("1", counter(heading.where(level: 1)).get().first()) + "-" + str(int(type-num) + 1)
}

#let table-figure(caption, table) = {
  figure(table, gap: 1em, caption: caption, supplement: [表], numbering: tbl-numering, kind: figure-kind-tbl)
}

#let code-figure(caption, code) = {
  figure(code, gap: 1em, caption: caption, supplement: [代码], numbering: code-numering, kind: figure-kind-code)
}

#let picture-figure(caption, picture) = {
  figure(picture, gap: 1em, caption: caption, supplement: [图], numbering: pic-numering, kind: figure-kind-pic)
}