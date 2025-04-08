#import "../lib.typ": *

= SQL引擎
#code-figure(
  // "tree src/sql",
  "SQL引擎的代码结构",
)[
```zsh
src/sql
├── engine
│   ├── engine.rs # 定义了SQL引擎的接口.
│   ├── local.rs # 本地存储的SQL引擎.
│   ├── mod.rs
│   ├── raft.rs # 基于Raft的分布式SQL引擎.
│   └── session.rs # 执行SQL语句, 并处理事务控制.
├── execution
│   ├── aggregate.rs # SQL的聚合操作, 如GROUP BY, COUNT等.
│   ├── execute.rs # 执行计划的执行器.
│   ├── join.rs # SQL的连接操作, 如JOIN, LEFT JOIN等.
│   ├── mod.rs
│   ├── source.rs # 负责提供数据源, 如表扫描, 主键扫描, 索引扫描等.
│   ├── transform.rs # SQL的转换操作, 如投影, 过滤, 限制, 排序等.
│   └── write.rs # SQL的写操作, 如INSERT, DELETE, UPDATE等.
├── mod.rs
├── parser
│   ├── ast.rs # 定义了SQL的抽象语法树(ast)的结构.
│   ├── lexer.rs # SQL的词法分析器, 将SQL语句转换为Token.
│   ├── mod.rs
│   └── parser.rs # SQL的语法分析器, 将Token转换为AST.
├── planner
│   ├── mod.rs
│   ├── optimizer.rs # 执行计划的优化器.
│   ├── plan.rs # 执行计划的结构与操作.
│   └── planner.rs # SQL解析以及执行计划的生成.
├── testscripts
│   └── ...
└── types
    ├── expression.rs # 定义了SQL的表达式.
    ├── mod.rs
    ├── schema.rs # 定义了SQL的表结构以及列结构.
    └── value.rs # 定义了SQL的基本数据类型以及数据类型枚举.


```
]

在看所有代码之前，通过它们对外的接口来了解整个SQL引擎的结构。除了第一个基本数据类型以外，我们通过一条SQL的生命周期来排序这些接口。

#code-figure(
  // "src/sql/types/mod.rs",
  "types对外暴露的接口",
)[
```rust
  // src/sql
  // ├── ...
  // └── types
  //     ├── expression.rs # 定义了SQL的表达式.
  //     ├── mod.rs
  //     ├── schema.rs # 定义了SQL的表结构以及列结构.
  //     └── value.rs # 定义了SQL的基本数据类型以及数据类型枚举.
  pub use expression::Expression;
  pub use schema::{Column, Table};
  pub use value::{DataType, Label, Row, Rows, Value};


  ```
]

这里暴露的东西还是比较简单的，就是SQL的基本数据类型，表结构，列结构，表达式以及多表查询的Lable等。

#code-figure(
  // "src/sql/engine/mod.rs",
  "engine对外暴露的接口",
)[
```rust
  // src/sql
  // ├── ...
  // └── engine
  //     ├── engine.rs # 定义了SQL引擎的接口.
  //     ├── local.rs # 本地存储的SQL引擎.
  //     ├── mod.rs
  //     ├── raft.rs # 基于Raft的分布式SQL引擎.
  //     └── session.rs # 执行SQL语句, 并处理事务控制.
  pub use engine::{Catalog, Engine, Transaction};
  pub use local::{Key, Local};
  pub use raft::{Raft, Status, Write};
  pub use session::{Session, StatementResult};


  ```
]

`local.rs`，`raft.rs`定义的两个引擎本别处理本地以及分布式事务

在`engine`模块中，`Session`通过`Engine`接口与具体的引擎交互，`Session`里面有个方法`execute`，用于执行SQL语句。`Session`里面的`StatementResult`用于表示SQL语句的执行结果。

#code-figure(
  // "src/sql/parse/mod.rs",
  "parse对外暴露的接口",
)[
```rust
  // src/sql
  // ├── ...
  // └── parser
  //     ├── ast.rs # 定义了SQL的抽象语法树(ast)的结构.
  //     ├── lexer.rs # SQL的词法分析器, 将SQL语句转换为Token.
  //     ├── mod.rs
  //     └── parser.rs # SQL的语法分析器, 将Token转换为AST.
  pub use lexer::{is_ident, Keyword, Lexer, Token};
  pub use parser::Parser;
  ```
]

在`execute`中，会调用`Parser`来解析SQL语句，解析的流程大概是：`Lexer`负责将SQL语句转换为Token，`Parser`负责将Token转换为AST。

AST就是可以被下面的`Planner`所使用的执行计划。

#code-figure(
  // "src/sql/planner/mod.rs",
  "planner对外暴露的接口",
)[
```rust
  // src/sql
  // ├── ...
  // └── planner
  //     ├── mod.rs
  //     ├── optimizer.rs # 执行计划的优化器.
  //     ├── plan.rs # 执行计划的结构与操作.
  //     └── planner.rs # SQL解析以及执行计划的生成.
  pub use plan::{Aggregate, Direction, Node, Plan};
  pub use planner::{Planner, Scope};

  #[cfg(test)]
  pub use optimizer::OPTIMIZERS;
  ```
]

`execute`从上一步获得了AST，然后调用`Plan::build()`来生成执行计划。生成的执行计划会被`Plan`中的`optimize()`方法调用optimize.rs中的优化方法来优化。

#code-figure(
  // "src/sql/execution/mod.rs",
  "execution对外暴露的接口",
)[
```rust
  // src/sql
  // │── ...
  // └── execution
  //     ├── aggregate.rs # SQL的聚合操作, 如GROUP BY, COUNT等.
  //     ├── execute.rs # 执行计划的执行器.
  //     ├── join.rs # SQL的连接操作, 如JOIN, LEFT JOIN等.
  //     ├── mod.rs
  //     ├── source.rs # 负责提供数据源, 如表扫描, 主键扫描, 索引扫描等.
  //     ├── transform.rs # SQL的转换操作, 如投影, 过滤, 限制, 排序等.
  //     └── write.rs # SQL的写操作, 如INSERT, DELETE, UPDATE等.
  pub use execute::{execute_plan, ExecutionResult};
  ```
]

最后执行计划会被`Plan::execution`执行，执行计划的结果会被`ExecutionResult`返回。

当然这里只是简单的说一下功能，具体的链路比现在的还要复杂一些。最终会在 @sql_summary 更详细描述脉络。

#include "chapter4/type.typ"
#include "chapter4/engine.typ"
#include "chapter4/parse.typ"
#include "chapter4/planner.typ"
#include "chapter4/execution.typ"
#include "chapter4/summary.typ"

