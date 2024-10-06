#import "../typst-book-template/book.typ": *
#let path-prefix = figure-root-path + "src/pics/"

= 共识算法Raft
#code(
  "tree src/raft",
  "Raft算法",
  ```zsh
  src/raft
  ├── log.rs
  ├── message.rs
  ├── mod.rs
  ├── node.rs
  ├── state.rs
  └── testscripts
      └── ...
  ```,
)

#include "chapter3/intro.typ"
#include "chapter3/message.typ"
#include "chapter3/node.typ"
#include "chapter3/log.typ"
#include "chapter3/summary.typ"