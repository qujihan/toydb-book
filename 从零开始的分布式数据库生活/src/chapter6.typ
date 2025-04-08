#import "../lib.typ": *

= 附录
#show heading.where(level: 2):it=>{
  pagebreak(weak: true)
  it
}

#include "chapter6/bitcask.typ"
#include "chapter6/isolation.typ"