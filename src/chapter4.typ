#import "../typst-book-template/book.typ": *
#let path-prefix = figure-root-path + "src/pics/"

= SQL引擎
#code(
  "tree src/sql",
  "SQL引擎的代码结构",
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
  ```,
)

在看所有代码之前，通过它们对外的接口来了解整个SQL引擎的结构。除了第一个基本数据类型以外，我们通过一条SQL的生命周期来排序这些接口。


#code("src/sql/types/mod.rs", "types对外暴露的接口")[
  ```rust
  /// .....
  pub use expression::Expression;
  pub use schema::{Column, Table};
  pub use value::{DataType, Label, Row, Rows, Value};
  ```
]

这里暴露的东西还是比较简单的，就是SQL的基本数据类型，表结构，列结构，表达式以及多表查询的Lable等。

#code("src/sql/engine/mod.rs", "engine对外暴露的接口")[
  ```rust
  /// .....
  pub use engine::{Catalog, Engine, Transaction};
  pub use local::{Key, Local};
  pub use raft::{Raft, Status, Write};
  pub use session::{Session, StatementResult};
  ```
]

`local.rs`，`raft.rs`定义的两个引擎本别处理本地以及分布式事务

在`engine`模块中，`Session`通过`Engine`接口与具体的引擎交互，`Session`里面有个方法`execute`，用于执行SQL语句。`Session`里面的`StatementResult`用于表示SQL语句的执行结果。

#code("src/sql/parse/mod.rs", "parse对外暴露的接口")[
  ```rust
  /// .....
  pub use lexer::{is_ident, Keyword, Lexer, Token};
  pub use parser::Parser;
  ```
]

在`execute`中，会调用`Parser`来解析SQL语句，解析的流程大概是：`Lexer`负责将SQL语句转换为Token，`Parser`负责将Token转换为AST。

AST就是可以被下面的`Planner`所使用的执行计划。

#code("src/sql/planner/mod.rs", "planner对外暴露的接口")[
  ```rust
  /// .....
  pub use plan::{Aggregate, Direction, Node, Plan};
  pub use planner::{Planner, Scope};

  #[cfg(test)]
  pub use optimizer::OPTIMIZERS;
  ```
]

`execute`从上一步获得了AST，然后调用`Plan::build()`来生成执行计划。生成的执行计划会被`Plan`中的`optimize()`方法调用optimize.rs中的优化方法来优化。

#code("src/sql/execution/mod.rs", "execution对外暴露的接口")[
  ```rust
  /// .....
  pub use execute::{execute_plan, ExecutionResult};
  ```
]

最后执行计划会被`Plan::execution`执行，执行计划的结果会被`ExecutionResult`返回。

当然这里只是简单的说一下功能，具体的链路比现在的还要复杂一些。最终会在 @sql_summary 更详细描述脉络。

== Type

=== 基本数据类型

现在看一下基本数据类型的定义。

为了简化，这里是支持少量的数据类型，不支持复杂数据类型等。

另外需要说一下，NULL以及NaN都被认为是不等于本事的值，所以`NULL != NULL`，`NaN != NaN`。但是在实际的代码中，NULL和NaN都认为是可以比较且相等的。这是为了对允许对这些值进行排序和处理（比如索引查找、桶聚合等场景）。


另外浮点数中的`-0.0 == 0.0`，`-NaN == NaN`都认为返回`true`。存储的时候会将`-0.0`规范化为`0.0`，`-NaN`规范化为`NaN`。

#code("src/sql/types/value.rs", "基本数据类型")[
  ```rust
  #[derive(Clone, Debug, Serialize, Deserialize)]
  pub enum Value {
      /// 空值
      Null,
      /// 布尔类型
      Boolean(bool),
      /// 64位有符号整数
      Integer(i64),
      /// 64位浮点数
      Float(f64),
      /// UTF-8编码的字符串
      String(String),
  }

  // 这里定义了 Value 相等的比较
  impl std::cmp::PartialEq for Value {
      fn eq(&self, other: &Self) -> bool {
          match (self, other) {
              // ...
              // 这里可以看到上面提到的 NaN == NaN 的情况
              // 另外
              // let a: f64 = 0.0;
              // let b: f64 = -0.0;
              // println!("{}", a == b); // true
              (Self::Float(l), Self::Float(r)) => l == r || l.is_nan() && r.is_nan(),
              // ...
              (l, r) => core::mem::discriminant(l) == core::mem::discriminant(r),
          }
      }
  }

  impl std::hash::Hash for Value {
      fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
          core::mem::discriminant(self).hash(state);
          // Normalize to treat +/-0.0 and +/-NAN as equal when hashing.
          // 这里调用了 normalize_ref 方法，这个方法会将 -0.0 规范化为 0.0
          // -NaN 规范化为 NaN
          match self.normalize_ref().as_ref() {
              Self::Null => {}
              Self::Boolean(v) => v.hash(state),
              Self::Integer(v) => v.hash(state),
              Self::Float(v) => v.to_bits().hash(state),
              Self::String(v) => v.hash(state),
          }
      }
  }

  // 这里定义的全序比较, 看一下就好
  impl Ord for Value {
      fn cmp(&self, other: &Self) -> std::cmp::Ordering {
          use std::cmp::Ordering::*;
          use Value::*;
          match (self, other) {
              (Null, Null) => Equal,
              (Boolean(a), Boolean(b)) => a.cmp(b),
              (Integer(a), Integer(b)) => a.cmp(b),
              (Integer(a), Float(b)) => (*a as f64).total_cmp(b),
              (Float(a), Integer(b)) => a.total_cmp(&(*b as f64)),
              (Float(a), Float(b)) => a.total_cmp(b),
              (String(a), String(b)) => a.cmp(b),

              (Null, _) => Less,
              (_, Null) => Greater,
              (Boolean(_), _) => Less,
              (_, Boolean(_)) => Greater,
              (Float(_), _) => Less,
              (_, Float(_)) => Greater,
              (Integer(_), _) => Less,
              (_, Integer(_)) => Greater,
              // String is ordered last.
          }
      }
  }

  // 定义了全序比较, 偏序比较直接调用全序比较就可以了
  impl PartialOrd for Value {
      fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
          Some(self.cmp(other))
      }
  }
  ```

]

=== Schema
=== 表达式
=== 总结

== Engine
=== SQL引擎的Engine接口
=== 本地存储的SQL引擎
=== 基于Raft的分布式SQL引擎
=== Session
=== 总结

== Parse
=== 抽象语法树
=== 词法解析
=== 语法解析
=== 总结

== Planner
=== Plan结构
=== 执行计划的生成
=== 执行计划的优化
=== 总结

== Execution
=== 执行器
=== 扫描操作
=== 聚合操作
=== 连接操作
=== 转换操作
=== 写操作
=== 总结

== 总结<sql_summary>