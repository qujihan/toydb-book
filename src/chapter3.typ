#import "../typst-book-template/book.typ": *
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

== Raft算法简单概括

== Raft实现中的取舍

== 总结