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

Raft共识算法是一种分布式一致性算法，它的设计目标是提供一种易于理解的一致性算法。Raft算法分为三个部分：领导选举、日志复制和安全性。具体的实现可以参考Raft论文#footnote("Raft 论文"+"https://raft.github.io/raft.pdf") #footnote("Raft 作者的博士论文: https://web.stanford.edu/~ouster/cgi-bin/papers/OngaroPhD.pdf") #footnote("Raft 官网: https://raft.github.io")的实现。


== Raft的实现
=== Message
=== Node
=== Log
=== 其他部分

== 总结