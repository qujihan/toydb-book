#import "../consts.typ": *

#let set-heading-style(body) = {
  show heading: set heading(numbering: (..nums)=>{
    let n = nums.pos().len()
    if n == 1 {
      numbering("第一章", ..nums)
    } else {
      numbering("1.1.1", ..nums)
    }
  })

  show ref.where(): it => {
    if it.element != none and it.element.func() == heading {
      let h = counter(heading).at(it.element.location())
      let n = h.len()
      link(it.element.location(), if n == 1 {
        numbering("第1章", ..h)
      } else {
        numbering("第1.1.1节", ..h)
      })
    } else {
      it
    }
  }

  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    text(size: 1.7em, it)
    v(1em)
  }

  show heading.where(level: 2): it => {
    text(size: 1.5em, it)
    v(0.7em)
  }

  show heading.where(level: 3): it => {
    text(size: 1.3em, it)
    v(0.5em)
  }

  body
}