#import "../typst-book-template/book.typ": *

= SQL引擎
#code(
  "tree src/sql",
  "SQL引擎的代码结构",
  ```zsh
  src/sql
  ├── engine
  │   ├── engine.rs
  │   ├── local.rs
  │   ├── mod.rs
  │   ├── raft.rs
  │   └── session.rs
  ├── execution
  │   ├── aggregate.rs
  │   ├── execute.rs
  │   ├── join.rs
  │   ├── mod.rs
  │   ├── source.rs
  │   ├── transform.rs
  │   └── write.rs
  ├── mod.rs
  ├── parser
  │   ├── ast.rs
  │   ├── lexer.rs
  │   ├── mod.rs
  │   └── parser.rs
  ├── planner
  │   ├── mod.rs
  │   ├── optimizer.rs
  │   ├── plan.rs
  │   └── planner.rs
  ├── testscripts
  │   └── ...
  └── types
      ├── expression.rs
      ├── mod.rs
      ├── schema.rs
      └── value.rs
  ```,
)
== Type
== Schemas
=== Schemas中的取舍
== Parsing解析
== Planning
== Execution
== 总结