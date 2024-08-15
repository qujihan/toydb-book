#import "../typst-book-template/book.typ": *
#let path-prefix = figure-root-path + "src/pics/"

= 附录
#show heading.where(level: 2):it=>{
  pagebreak(weak: true)
  it
}

#include "chapter6/bitcask.typ"
#include "chapter6/isolation.typ"