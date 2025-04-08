#import "../../lib.typ": *

== Type

=== 基本数据类型

现在看一下基本数据类型的定义。

为了简化，这里是支持少量的数据类型，不支持复杂数据类型等。

另外需要说一下，NULL以及NaN都被认为是不等于本身的值，所以理论上`NULL != NULL`，`NaN != NaN`。但是在实际的代码中，NULL和NaN都认为是可以比较且相等的。这是为了对允许对这些值进行排序和处理（比如索引查找、桶聚合等场景）。

另外浮点数中的`-0.0 == 0.0`，`-NaN == NaN`都认为返回`true`。存储的时候会将`-0.0`规范化为`0.0`，`-NaN`规范化为`NaN`。

#code-figure(
  // "src/sql/types/value.rs",
  "基本数据类型",
)[
```rust
  /// 支持的数据类型
  #[derive(Clone, Copy, Debug, Hash, PartialEq, Serialize, Deserialize)]
  pub enum DataType {
      Boolean, // 布尔类型
      Integer, // 64位有符号整数
      Float,   // 64位浮点数
      String,  // UTF-8编码的字符串
  }

  /// 数据的值
  #[derive(Clone, Debug, Serialize, Deserialize)]
  pub enum Value {
      Null,           // 空值
      Boolean(bool),  // 布尔类型
      Integer(i64),   // 64位有符号整数
      Float(f64),     // 64位浮点数
      String(String), // UTF-8编码的字符串
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
              // ..省略大部分简单代码..
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

  // 这里是实现偏序比较, 在定义了全序比较以后, 偏序比较直接调用全序比较就可以了
  impl PartialOrd for Value {
      fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
          Some(self.cmp(other))
      }
  }
  ```

]

#code-figure(
  // "src/sql/types/value.rs",
  "Value 的具体实现",
)[
```rust
  impl Value {
      /// 加法操作
      pub fn checked_add(&self, other: &Self) -> Result<Self> { ...  }
      /// 除法操作
      pub fn checked_div(&self, other: &Self) -> Result<Self> { ...  }
      /// 乘法操作
      pub fn checked_mul(&self, other: &Self) -> Result<Self> { ...  }
      /// 幂运算
      pub fn checked_pow(&self, other: &Self) -> Result<Self> { ...  }
      /// 取余操作
      pub fn checked_rem(&self, other: &Self) -> Result<Self> { ...  }
      /// 减法操作
      pub fn checked_sub(&self, other: &Self) -> Result<Self> { ...  }
      /// 返回数据类型
      /// 这里可以看到Rust的表达能力挺强的
      pub fn datatype(&self) -> Option<DataType> {
          match self {
              Self::Null => None,
              Self::Boolean(_) => Some(DataType::Boolean),
              Self::Integer(_) => Some(DataType::Integer),
              Self::Float(_) => Some(DataType::Float),
              Self::String(_) => Some(DataType::String),
          }
      }
      /// 返回 true 如果值是未定义的(NULL 或 NaN).
      pub fn is_undefined(&self) -> bool { ... }

      /// 原地规范化一个值.
      /// 目前将 -0.0 和 -NAN 规范化为 0.0 和 NAN, 这是主键和索引查找中使用的规范值.
      pub fn normalize(&mut self) {
          if let Cow::Owned(normalized) = self.normalize_ref() {
              *self = normalized;
          }
      }

      /// 将一个 borrow 的值规范化.
      /// 目前将 -0.0 和 -NAN 规范化为 0.0 和 NAN, 这是主键和索引查找中使用的规范值.
      /// 当值发生变化时, 返回 Cow::Owned, 以避免在值不变的常见情况下分配内存.
      pub fn normalize_ref(&self) -> Cow<'_, Self> {
          if let Self::Float(f) = self {
              if (f.is_nan() || *f == -0.0) && f.is_sign_negative() {
                  return Cow::Owned(Self::Float(-f));
              }
          }
          Cow::Borrowed(self)
      }

      /// 如果值已经规范化, 返回 true.
      /// 这里还挺有意思, 通过 Cow::Borrowed 来判断是否规范化.
      /// 如果是 Cow::Owned(_), 说明已经规范化了, 返回false.
      /// 这里的 Cow::Borrowed(_), 说明传进去的值是已经规范化的， 返回true.
      pub fn is_normalized(&self) -> bool {
          matches!(self.normalize_ref(), Cow::Borrowed(_))
      }
  }


  impl std::fmt::Display for Value {
      fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result { ... }
  }

  /// 定义了 Value 与 Rust 基本数据类型的相互转换.
  impl From<bool> for Value { fn from(v: bool) -> Self { Value::Boolean(v) } }
  impl From<f64> for Value { fn from(v: f64) -> Self { Value::Float(v) } }
  impl From<i64> for Value { fn from(v: i64) -> Self { Value::Integer(v) } }
  impl From<String> for Value { fn from(v: String) -> Self { Value::String(v) } }
  impl From<&str> for Value { fn from(v: &str) -> Self { Value::String(v.to_owned()) } }
  impl TryFrom<Value> for bool { ... }
  impl TryFrom<Value> for f64 { ... }
  impl TryFrom<Value> for i64 { ... }
  impl TryFrom<Value> for String { ... }

  /// 定义了 Value 到 Cow<'_, Value> 的转换.
  impl<'a> From<&'a Value> for Cow<'a, Value> {
      fn from(v: &'a Value) -> Self { Cow::Borrowed(v) }
  }
  ```
]

这一部分看起来是比较简单的，但是写起来需要考虑的东西还是挺多的，比如macth中的顺序之类的，都是一些小细节。但是看起来难度并没有很大，这里就不再展开了。

下面看一下其他的类型。

#code-figure(
  // "",
  "",
)[
```rust
  /// A row of values.
  pub type Row = Vec<Value>;

  /// A row iterator.
  pub type Rows = Box<dyn RowIterator>;

  /// A row iterator trait, which requires the iterator to be both clonable and
  /// object-safe. Cloning is needed to be able to reset an iterator back to an
  /// initial state, e.g. during nested loop joins. It has a blanket
  /// implementation for all matching iterators.
  pub trait RowIterator: Iterator<Item = Result<Row>> + DynClone {}
  impl<I: Iterator<Item = Result<Row>> + DynClone> RowIterator for I {}
  dyn_clone::clone_trait_object!(RowIterator);
  ```
]

#code-figure(
  // "",
  "",
)[
```rust
  /// A column label, used in query results and plans.
  #[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
  pub enum Label {
      /// No label.
      None,
      /// An unqualified column name.
      Unqualified(String),
      /// A fully qualified table/column name.
      Qualified(String, String),
  }

  impl std::fmt::Display for Label {
      fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
          match self {
              Self::None => write!(f, ""),
              Self::Unqualified(name) => write!(f, "{name}"),
              Self::Qualified(table, column) => write!(f, "{table}.{column}"),
          }
      }
  }

  impl Label {
      /// Formats the label as a short column header.
      pub fn as_header(&self) -> &str {
          match self {
              Self::Qualified(_, column) | Self::Unqualified(column) => column.as_str(),
              Self::None => "?",
          }
      }
  }

  impl From<Label> for ast::Expression {
      /// Builds an ast::Expression::Column for a label. Can't be None.
      fn from(label: Label) -> Self {
          match label {
              Label::Qualified(table, column) => ast::Expression::Column(Some(table), column),
              Label::Unqualified(column) => ast::Expression::Column(None, column),
              Label::None => panic!("can't convert None label to AST expression"), // shouldn't happen
          }
      }
  }

  impl From<Option<String>> for Label {
      fn from(name: Option<String>) -> Self {
          name.map(Label::Unqualified).unwrap_or(Label::None)
      }
  }


  ```
]

=== Schema

在 Schema 中定义了Table 以及 Column 的结构。

#code-figure(
  // "src/sql/types/schema.rs",
  "Colume 以及 Table 的结构",
)[
```rust
  /// A table schema, which specifies its data structure and constraints.
  ///
  /// Tables can't change after they are created. There is no ALTER TABLE nor
  /// CREATE/DROP INDEX -- only CREATE TABLE and DROP TABLE.
  #[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
  pub struct Table {
      /// The table name. Can't be empty.
      pub name: String,
      /// The primary key column index. A table must have a primary key, and it
      /// can only be a single column.
      pub primary_key: usize,
      /// The table's columns. Must have at least one.
      pub columns: Vec<Column>,
  }

  /// A table column.
  #[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
  pub struct Column {
      /// Column name. Can't be empty.
      pub name: String,
      /// Column datatype.
      pub datatype: DataType,
      /// Whether the column allows null values. Not legal for primary keys.
      pub nullable: bool,
      /// The column's default value. If None, the user must specify an explicit
      /// value. Must match the column datatype. Nullable columns require a
      /// default (often Null), and Null is only a valid default when nullable.
      pub default: Option<Value>,
      /// Whether the column should only allow unique values (ignoring NULLs).
      /// Must be true for a primary key column.
      pub unique: bool,
      /// Whether the column should have a secondary index. Must be false for
      /// primary keys, which are the implicit primary index. Must be true for
      /// unique or reference columns.
      pub index: bool,
      /// If set, this column is a foreign key reference to the given table's
      /// primary key. Must be of the same type as the target primary key.
      pub references: Option<String>,
  }
  ```
]
这里的表结构还是比较简单的，只有基本的表名，主键所在的列号，所有的列。每一列有列名，数据类型，是否允许为空，默认值，是否唯一，是否有索引等。

#code-figure(
  //   "",
  "",
)[
```rust
  impl std::fmt::Display for Table {
      fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // ...
      }
  }

  impl Table {
      /// Validates the table schema, using the catalog to validate foreign key
      /// references.
      pub fn validate(&self, catalog: &impl Catalog) -> Result<()> {
          if self.name.is_empty() {
              return errinput!("table name can't be empty");
          }
          if self.columns.is_empty() {
              return errinput!("table has no columns");
          }
          if self.columns.get(self.primary_key).is_none() {
              return errinput!("invalid primary key index");
          }

          for (i, column) in self.columns.iter().enumerate() {
              if column.name.is_empty() {
                  return errinput!("column name can't be empty");
              }
              let (cname, ctype) = (&column.name, &column.datatype); // for formatting convenience

              // Validate primary key.
              let is_primary_key = i == self.primary_key;
              if is_primary_key {
                  if column.nullable {
                      return errinput!("primary key {cname} cannot be nullable");
                  }
                  if !column.unique {
                      return errinput!("primary key {cname} must be unique");
                  }
                  if column.index {
                      return errinput!("primary key {cname} can't have an index");
                  }
              }

              // Validate default value.
              match column.default.as_ref().map(|v| v.datatype()) {
                  None if column.nullable => {
                      return errinput!("nullable column {cname} must have a default value")
                  }
                  Some(None) if !column.nullable => {
                      return errinput!("invalid NULL default for non-nullable column {cname}")
                  }
                  Some(Some(vtype)) if vtype != column.datatype => {
                      return errinput!("invalid default type {vtype} for {ctype} column {cname}");
                  }
                  Some(_) | None => {}
              }

              // Validate unique index.
              if column.unique && !column.index && !is_primary_key {
                  return errinput!("unique column {cname} must have a secondary index");
              }

              // Validate references.
              if let Some(reference) = &column.references {
                  if !column.index && !is_primary_key {
                      return errinput!("reference column {cname} must have a secondary index");
                  }
                  let reftype = if reference == &self.name {
                      self.columns[self.primary_key].datatype
                  } else if let Some(target) = catalog.get_table(reference)? {
                      target.columns[target.primary_key].datatype
                  } else {
                      return errinput!("unknown table {reference} referenced by column {cname}");
                  };
                  if column.datatype != reftype {
                      return errinput!("can't reference {reftype} primary key of {reference} from {ctype} column {cname}");
                  }
              }
          }
          Ok(())
      }

      /// Validates a row, including uniqueness and reference checks using the
      /// given transaction.
      ///
      /// If update is true, the row replaces an existing entry with the same
      /// primary key. Otherwise, it is an insert. Primary key changes are
      /// implemented as a delete+insert.
      ///
      /// Validating uniqueness and references individually for each row is not
      /// performant, but it's fine for our purposes.
      pub fn validate_row(&self, row: &[Value], update: bool, txn: &impl Transaction) -> Result<()> {
          if row.len() != self.columns.len() {
              return errinput!("invalid row size for table {}", self.name);
          }

          // Validate primary key.
          let id = &row[self.primary_key];
          let idslice = &row[self.primary_key..=self.primary_key];
          if id.is_undefined() {
              return errinput!("invalid primary key {id}");
          }
          if !update && !txn.get(&self.name, idslice)?.is_empty() {
              return errinput!("primary key {id} already exists");
          }

          for (i, (column, value)) in self.columns.iter().zip(row).enumerate() {
              let (cname, ctype) = (&column.name, &column.datatype);
              let valueslice = &row[i..=i];

              // Validate datatype.
              if let Some(ref vtype) = value.datatype() {
                  if vtype != ctype {
                      return errinput!("invalid datatype {vtype} for {ctype} column {cname}");
                  }
              }
              if value == &Value::Null && !column.nullable {
                  return errinput!("NULL value not allowed for column {cname}");
              }

              // Validate outgoing references.
              if let Some(target) = &column.references {
                  match value {
                      // NB: NaN is not a valid primary key, and not valid as a
                      // missing foreign key marker.
                      Value::Null => {}
                      v if target == &self.name && v == id => {}
                      v if txn.get(target, valueslice)?.is_empty() => {
                          return errinput!("reference {v} not in table {target}");
                      }
                      _ => {}
                  }
              }

              // Validate uniqueness constraints. Unique columns are indexed.
              if column.unique && i != self.primary_key && !value.is_undefined() {
                  let mut index = txn.lookup_index(&self.name, &column.name, valueslice)?;
                  if update {
                      index.remove(id); // ignore existing version of this row
                  }
                  if !index.is_empty() {
                      return errinput!("value {value} already in unique column {cname}");
                  }
              }
          }
          Ok(())
      }
  }
  ```
]
=== 表达式
#code-figure(
  // "src/sql/types/expression.rs",
  "Expression 的定义",
)[
```rust
  /// An expression, made up of nested operations and values. Values are either
  /// constants or dynamic column references. Evaluates to a final value during
  /// query execution, using row values for column references.
  ///
  /// Since this is a recursive data structure, we have to box each child
  /// expression, which incurs a heap allocation per expression node. There are
  /// clever ways to avoid this, but we keep it simple.
  #[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
  pub enum Expression {
      /// A constant value.
      Constant(Value),
      /// A column reference. Used as row index when evaluating expressions.
      Column(usize),

      /// Logical AND of two booleans: a AND b.
      And(Box<Expression>, Box<Expression>),
      /// Logical OR of two booleans: a OR b.
      Or(Box<Expression>, Box<Expression>),
      /// Logical NOT of a boolean: NOT a.
      Not(Box<Expression>),

      /// Equality comparison of two values: a = b.
      Equal(Box<Expression>, Box<Expression>),
      /// Greater than comparison of two values: a > b.
      GreaterThan(Box<Expression>, Box<Expression>),
      /// Less than comparison of two values: a < b.
      LessThan(Box<Expression>, Box<Expression>),
      /// Checks for the given value: IS NULL or IS NAN.
      Is(Box<Expression>, Value),

      /// Adds two numbers: a + b.
      Add(Box<Expression>, Box<Expression>),
      /// Divides two numbers: a / b.
      Divide(Box<Expression>, Box<Expression>),
      /// Exponentiates two numbers, i.e. a ^ b.
      Exponentiate(Box<Expression>, Box<Expression>),
      /// Takes the factorial of a number: 4! = 4*3*2*1.
      Factorial(Box<Expression>),
      /// The identify function, which simply returns the same number: +a.
      Identity(Box<Expression>),
      /// Multiplies two numbers: a * b.
      Multiply(Box<Expression>, Box<Expression>),
      /// Negates the given number: -a.
      Negate(Box<Expression>),
      /// The remainder after dividing two numbers: a % b.
      Remainder(Box<Expression>, Box<Expression>),
      /// Takes the square root of a number: √a.
      SquareRoot(Box<Expression>),
      /// Subtracts two numbers: a - b.
      Subtract(Box<Expression>, Box<Expression>),

      // Checks if a string matches a pattern: a LIKE b.
      Like(Box<Expression>, Box<Expression>),
  }
  ```
]

#code-figure(
  // "src/sql/types/expression.rs",
  "Expression 的实现",
)[
```rust
  impl Expression {
      /// Formats the expression, using the given plan node to look up labels for
      /// numeric column references.
      pub fn format(&self, node: &Node) -> String {
          use Expression::*;

          // Precedence levels, for grouping. Matches the parser precedence.
          fn precedence(expr: &Expression) -> u8 {
              match expr {
                  Column(_) | Constant(_) | SquareRoot(_) => 11,
                  Identity(_) | Negate(_) => 10,
                  Factorial(_) => 9,
                  Exponentiate(_, _) => 8,
                  Multiply(_, _) | Divide(_, _) | Remainder(_, _) => 7,
                  Add(_, _) | Subtract(_, _) => 6,
                  GreaterThan(_, _) | LessThan(_, _) => 5,
                  Equal(_, _) | Like(_, _) | Is(_, _) => 4,
                  Not(_) => 3,
                  And(_, _) => 2,
                  Or(_, _) => 1,
              }
          }

          // Helper to format a boxed expression, grouping it with () if needed.
          let format = |expr: &Expression| {
              let mut string = expr.format(node);
              if precedence(expr) < precedence(self) {
                  string = format!("({string})");
              }
              string
          };

          match self {
              Constant(value) => format!("{value}"),
              Column(index) => match node.column_label(*index) {
                  Label::None => format!("#{index}"),
                  label => format!("{label}"),
              },

              And(lhs, rhs) => format!("{} AND {}", format(lhs), format(rhs)),
              Or(lhs, rhs) => format!("{} OR {}", format(lhs), format(rhs)),
              Not(expr) => format!("NOT {}", format(expr)),

              Equal(lhs, rhs) => format!("{} = {}", format(lhs), format(rhs)),
              GreaterThan(lhs, rhs) => format!("{} > {}", format(lhs), format(rhs)),
              LessThan(lhs, rhs) => format!("{} < {}", format(lhs), format(rhs)),
              Is(expr, Value::Null) => format!("{} IS NULL", format(expr)),
              Is(expr, Value::Float(f)) if f.is_nan() => format!("{} IS NAN", format(expr)),
              Is(_, v) => panic!("unexpected IS value {v}"),

              Add(lhs, rhs) => format!("{} + {}", format(lhs), format(rhs)),
              Divide(lhs, rhs) => format!("{} / {}", format(lhs), format(rhs)),
              Exponentiate(lhs, rhs) => format!("{} ^ {}", format(lhs), format(rhs)),
              Factorial(expr) => format!("{}!", format(expr)),
              Identity(expr) => format(expr),
              Multiply(lhs, rhs) => format!("{} * {}", format(lhs), format(rhs)),
              Negate(expr) => format!("-{}", format(expr)),
              Remainder(lhs, rhs) => format!("{} % {}", format(lhs), format(rhs)),
              SquareRoot(expr) => format!("sqrt({})", format(expr)),
              Subtract(lhs, rhs) => format!("{} - {}", format(lhs), format(rhs)),

              Like(lhs, rhs) => format!("{} LIKE {}", format(lhs), format(rhs)),
          }
      }

      /// Formats a constant expression. Errors on column references.
      pub fn format_constant(&self) -> String {
          self.format(&Node::Nothing { columns: Vec::new() })
      }

      /// Evaluates an expression, returning a value. Column references look up
      /// values in the given row. If None, any Column references will panic.
      pub fn evaluate(&self, row: Option<&Row>) -> Result<Value> {
          use Value::*;
          Ok(match self {
              // Constant values return themselves.
              Self::Constant(value) => value.clone(),

              // Column references look up a row value. The planner ensures that
              // only constant expressions are evaluated without a row.
              Self::Column(index) => match row {
                  Some(row) => row.get(*index).expect("short row").clone(),
                  None => panic!("can't reference column {index} with constant evaluation"),
              },

              // Logical AND. Inputs must be boolean or NULL. NULLs generally
              // yield NULL, except the special case NULL AND false == false.
              Self::And(lhs, rhs) => match (lhs.evaluate(row)?, rhs.evaluate(row)?) {
                  (Boolean(lhs), Boolean(rhs)) => Boolean(lhs && rhs),
                  (Boolean(b), Null) | (Null, Boolean(b)) if !b => Boolean(false),
                  (Boolean(_), Null) | (Null, Boolean(_)) | (Null, Null) => Null,
                  (lhs, rhs) => return errinput!("can't AND {lhs} and {rhs}"),
              },

              // Logical OR. Inputs must be boolean or NULL. NULLs generally
              // yield NULL, except the special case NULL OR true == true.
              Self::Or(lhs, rhs) => match (lhs.evaluate(row)?, rhs.evaluate(row)?) {
                  (Boolean(lhs), Boolean(rhs)) => Boolean(lhs || rhs),
                  (Boolean(b), Null) | (Null, Boolean(b)) if b => Boolean(true),
                  (Boolean(_), Null) | (Null, Boolean(_)) | (Null, Null) => Null,
                  (lhs, rhs) => return errinput!("can't OR {lhs} and {rhs}"),
              },

              // Logical NOT. Input must be boolean or NULL.
              Self::Not(expr) => match expr.evaluate(row)? {
                  Boolean(b) => Boolean(!b),
                  Null => Null,
                  value => return errinput!("can't NOT {value}"),
              },

              // Comparisons. Must be of same type, except floats and integers
              // which are interchangeable. NULLs yield NULL, NaNs yield NaN.
              //
              // Does not dispatch to Value.cmp() because sorting and comparisons
              // are different for f64 NaN and -0.0 values.
              #[allow(clippy::float_cmp)]
              Self::Equal(lhs, rhs) => match (lhs.evaluate(row)?, rhs.evaluate(row)?) {
                  (Boolean(lhs), Boolean(rhs)) => Boolean(lhs == rhs),
                  (Integer(lhs), Integer(rhs)) => Boolean(lhs == rhs),
                  (Integer(lhs), Float(rhs)) => Boolean(lhs as f64 == rhs),
                  (Float(lhs), Integer(rhs)) => Boolean(lhs == rhs as f64),
                  (Float(lhs), Float(rhs)) => Boolean(lhs == rhs),
                  (String(lhs), String(rhs)) => Boolean(lhs == rhs),
                  (Null, _) | (_, Null) => Null,
                  (lhs, rhs) => return errinput!("can't compare {lhs} and {rhs}"),
              },

              Self::GreaterThan(lhs, rhs) => match (lhs.evaluate(row)?, rhs.evaluate(row)?) {
                  #[allow(clippy::bool_comparison)]
                  (Boolean(lhs), Boolean(rhs)) => Boolean(lhs > rhs),
                  (Integer(lhs), Integer(rhs)) => Boolean(lhs > rhs),
                  (Integer(lhs), Float(rhs)) => Boolean(lhs as f64 > rhs),
                  (Float(lhs), Integer(rhs)) => Boolean(lhs > rhs as f64),
                  (Float(lhs), Float(rhs)) => Boolean(lhs > rhs),
                  (String(lhs), String(rhs)) => Boolean(lhs > rhs),
                  (Null, _) | (_, Null) => Null,
                  (lhs, rhs) => return errinput!("can't compare {lhs} and {rhs}"),
              },

              Self::LessThan(lhs, rhs) => match (lhs.evaluate(row)?, rhs.evaluate(row)?) {
                  #[allow(clippy::bool_comparison)]
                  (Boolean(lhs), Boolean(rhs)) => Boolean(lhs < rhs),
                  (Integer(lhs), Integer(rhs)) => Boolean(lhs < rhs),
                  (Integer(lhs), Float(rhs)) => Boolean((lhs as f64) < rhs),
                  (Float(lhs), Integer(rhs)) => Boolean(lhs < rhs as f64),
                  (Float(lhs), Float(rhs)) => Boolean(lhs < rhs),
                  (String(lhs), String(rhs)) => Boolean(lhs < rhs),
                  (Null, _) | (_, Null) => Null,
                  (lhs, rhs) => return errinput!("can't compare {lhs} and {rhs}"),
              },

              Self::Is(expr, Null) => Boolean(expr.evaluate(row)? == Null),
              Self::Is(expr, Float(f)) if f.is_nan() => match expr.evaluate(row)? {
                  Float(f) => Boolean(f.is_nan()),
                  Null => Null,
                  v => return errinput!("IS NAN can't be used with {}", v.datatype().unwrap()),
              },
              Self::Is(_, v) => panic!("invalid IS value {v}"), // enforced by parser

              // Mathematical operations. Inputs must be numbers, but integers and
              // floats are interchangeable (float when mixed). NULLs yield NULL.
              // Errors on integer overflow, while floats yield infinity or NaN.
              Self::Add(lhs, rhs) => lhs.evaluate(row)?.checked_add(&rhs.evaluate(row)?)?,
              Self::Divide(lhs, rhs) => lhs.evaluate(row)?.checked_div(&rhs.evaluate(row)?)?,
              Self::Exponentiate(lhs, rhs) => lhs.evaluate(row)?.checked_pow(&rhs.evaluate(row)?)?,
              Self::Factorial(expr) => match expr.evaluate(row)? {
                  Integer(i) if i < 0 => return errinput!("can't take factorial of negative number"),
                  Integer(i) => (1..=i).try_fold(Integer(1), |p, i| p.checked_mul(&Integer(i)))?,
                  Null => Null,
                  value => return errinput!("can't take factorial of {value}"),
              },
              Self::Identity(expr) => match expr.evaluate(row)? {
                  v @ (Integer(_) | Float(_) | Null) => v,
                  expr => return errinput!("can't take the identity of {expr}"),
              },
              Self::Multiply(lhs, rhs) => lhs.evaluate(row)?.checked_mul(&rhs.evaluate(row)?)?,
              Self::Negate(expr) => match expr.evaluate(row)? {
                  Integer(i) => Integer(-i),
                  Float(f) => Float(-f),
                  Null => Null,
                  value => return errinput!("can't negate {value}"),
              },
              Self::Remainder(lhs, rhs) => lhs.evaluate(row)?.checked_rem(&rhs.evaluate(row)?)?,
              Self::SquareRoot(expr) => match expr.evaluate(row)? {
                  Integer(i) if i < 0 => return errinput!("can't take negative square root"),
                  Integer(i) => Float((i as f64).sqrt()),
                  Float(f) => Float(f.sqrt()),
                  Null => Null,
                  value => return errinput!("can't take square root of {value}"),
              },
              Self::Subtract(lhs, rhs) => lhs.evaluate(row)?.checked_sub(&rhs.evaluate(row)?)?,

              // LIKE pattern matching, using _ and % as single- and
              // multi-character wildcards. Inputs must be strings. NULLs yield
              // NULL. There's no support for escaping an _ and %.
              Self::Like(lhs, rhs) => match (lhs.evaluate(row)?, rhs.evaluate(row)?) {
                  (String(lhs), String(rhs)) => {
                      // We could precompile the pattern if it's constant, instead
                      // of recompiling it for every row, but this is fine.
                      let pattern =
                          format!("^{}$", regex::escape(&rhs).replace('%', ".*").replace('_', "."));
                      Boolean(regex::Regex::new(&pattern)?.is_match(&lhs))
                  }
                  (String(_), Null) | (Null, String(_)) | (Null, Null) => Null,
                  (lhs, rhs) => return errinput!("can't LIKE {lhs} and {rhs}"),
              },
          })
      }

      /// Recursively walks the expression tree depth-first, calling the given
      /// closure until it returns false. Returns true otherwise.
      pub fn walk(&self, visitor: &mut impl FnMut(&Expression) -> bool) -> bool {
          if !visitor(self) {
              return false;
          }
          match self {
              Self::Add(lhs, rhs)
              | Self::And(lhs, rhs)
              | Self::Divide(lhs, rhs)
              | Self::Equal(lhs, rhs)
              | Self::Exponentiate(lhs, rhs)
              | Self::GreaterThan(lhs, rhs)
              | Self::LessThan(lhs, rhs)
              | Self::Like(lhs, rhs)
              | Self::Multiply(lhs, rhs)
              | Self::Or(lhs, rhs)
              | Self::Remainder(lhs, rhs)
              | Self::Subtract(lhs, rhs) => lhs.walk(visitor) && rhs.walk(visitor),

              Self::Factorial(expr)
              | Self::Identity(expr)
              | Self::Is(expr, _)
              | Self::Negate(expr)
              | Self::Not(expr)
              | Self::SquareRoot(expr) => expr.walk(visitor),

              Self::Constant(_) | Self::Column(_) => true,
          }
      }

      /// Recursively walks the expression tree depth-first, calling the given
      /// closure until it returns true. Returns false otherwise. This is the
      /// inverse of walk().
      pub fn contains(&self, visitor: &impl Fn(&Expression) -> bool) -> bool {
          !self.walk(&mut |e| !visitor(e))
      }

      /// Transforms the expression by recursively applying the given closures
      /// depth-first to each node before/after descending.
      pub fn transform(
          mut self,
          before: &impl Fn(Self) -> Result<Self>,
          after: &impl Fn(Self) -> Result<Self>,
      ) -> Result<Self> {
          // Helper for transforming boxed expressions.
          let xform = |mut expr: Box<Expression>| -> Result<Box<Expression>> {
              *expr = expr.transform(before, after)?;
              Ok(expr)
          };

          self = before(self)?;
          self = match self {
              Self::Add(lhs, rhs) => Self::Add(xform(lhs)?, xform(rhs)?),
              Self::And(lhs, rhs) => Self::And(xform(lhs)?, xform(rhs)?),
              Self::Divide(lhs, rhs) => Self::Divide(xform(lhs)?, xform(rhs)?),
              Self::Equal(lhs, rhs) => Self::Equal(xform(lhs)?, xform(rhs)?),
              Self::Exponentiate(lhs, rhs) => Self::Exponentiate(xform(lhs)?, xform(rhs)?),
              Self::GreaterThan(lhs, rhs) => Self::GreaterThan(xform(lhs)?, xform(rhs)?),
              Self::LessThan(lhs, rhs) => Self::LessThan(xform(lhs)?, xform(rhs)?),
              Self::Like(lhs, rhs) => Self::Like(xform(lhs)?, xform(rhs)?),
              Self::Multiply(lhs, rhs) => Self::Multiply(xform(lhs)?, xform(rhs)?),
              Self::Or(lhs, rhs) => Self::Or(xform(lhs)?, xform(rhs)?),
              Self::Remainder(lhs, rhs) => Self::Remainder(xform(lhs)?, xform(rhs)?),
              Self::SquareRoot(expr) => Self::SquareRoot(xform(expr)?),
              Self::Subtract(lhs, rhs) => Self::Subtract(xform(lhs)?, xform(rhs)?),

              Self::Factorial(expr) => Self::Factorial(xform(expr)?),
              Self::Identity(expr) => Self::Identity(xform(expr)?),
              Self::Is(expr, value) => Self::Is(xform(expr)?, value),
              Self::Negate(expr) => Self::Negate(xform(expr)?),
              Self::Not(expr) => Self::Not(xform(expr)?),

              expr @ (Self::Constant(_) | Self::Column(_)) => expr,
          };
          self = after(self)?;
          Ok(self)
      }

      /// Converts the expression into conjunctive normal form, i.e. an AND of
      /// ORs, which is useful when optimizing plans. This is done by converting
      /// to negation normal form and then applying De Morgan's distributive law.
      pub fn into_cnf(self) -> Self {
          use Expression::*;
          let xform = |expr| {
              // We can't use a single match, since it needs deref patterns.
              let Or(lhs, rhs) = expr else { return expr };
              match (*lhs, *rhs) {
                  // (x AND y) OR z → (x OR z) AND (y OR z)
                  (And(l, r), rhs) => And(Or(l, rhs.clone().into()).into(), Or(r, rhs.into()).into()),
                  // x OR (y AND z) → (x OR y) AND (x OR z)
                  (lhs, And(l, r)) => And(Or(lhs.clone().into(), l).into(), Or(lhs.into(), r).into()),
                  // Otherwise, do nothing.
                  (lhs, rhs) => Or(lhs.into(), rhs.into()),
              }
          };
          self.into_nnf().transform(&|e| Ok(xform(e)), &Ok).unwrap() // infallible
      }

      /// Converts the expression into negation normal form. This pushes NOT
      /// operators into the tree using De Morgan's laws, such that they're always
      /// below other logical operators. It is a useful intermediate form for
      /// applying other logical normalizations.
      pub fn into_nnf(self) -> Self {
          use Expression::*;
          let xform = |expr| {
              let Not(inner) = expr else { return expr };
              match *inner {
                  // NOT (x AND y) → (NOT x) OR (NOT y)
                  And(lhs, rhs) => Or(Not(lhs).into(), Not(rhs).into()),
                  // NOT (x OR y) → (NOT x) AND (NOT y)
                  Or(lhs, rhs) => And(Not(lhs).into(), Not(rhs).into()),
                  // NOT NOT x → x
                  Not(inner) => *inner,
                  // Otherwise, do nothing.
                  expr => Not(expr.into()),
              }
          };
          self.transform(&|e| Ok(xform(e)), &Ok).unwrap() // never fails
      }

      /// Converts the expression into conjunctive normal form as a vector of
      /// ANDed expressions (instead of nested ANDs).
      pub fn into_cnf_vec(self) -> Vec<Self> {
          let mut cnf = Vec::new();
          let mut stack = vec![self.into_cnf()];
          while let Some(expr) = stack.pop() {
              if let Self::And(lhs, rhs) = expr {
                  stack.extend([*rhs, *lhs]); // push lhs last to pop it first
              } else {
                  cnf.push(expr);
              }
          }
          cnf
      }

      /// Creates an expression by ANDing together a vector, or None if empty.
      pub fn and_vec(exprs: Vec<Expression>) -> Option<Self> {
          let mut iter = exprs.into_iter();
          let mut expr = iter.next()?;
          for rhs in iter {
              expr = Expression::And(expr.into(), rhs.into());
          }
          Some(expr)
      }

      /// Checks if an expression is a single column lookup (i.e. a disjunction of
      /// = or IS NULL/NAN for a single column), returning the column index.
      pub fn is_column_lookup(&self) -> Option<usize> {
          use Expression::*;
          match &self {
              // Column/constant equality can use index lookups. NULL and NaN are
              // handled in into_column_values().
              Equal(lhs, rhs) => match (lhs.as_ref(), rhs.as_ref()) {
                  (Column(c), Constant(_)) | (Constant(_), Column(c)) => Some(*c),
                  _ => None,
              },
              // IS NULL and IS NAN can use index lookups.
              Is(expr, _) => match expr.as_ref() {
                  Column(c) => Some(*c),
                  _ => None,
              },
              // All OR branches must be lookups on the same column:
              // id = 1 OR id = 2 OR id = 3.
              Or(lhs, rhs) => match (lhs.is_column_lookup(), rhs.is_column_lookup()) {
                  (Some(l), Some(r)) if l == r => Some(l),
                  _ => None,
              },
              _ => None,
          }
      }

      /// Extracts column lookup values for the given column. Panics if the
      /// expression isn't a lookup of the given column, i.e. is_column_lookup()
      /// must return true for the expression.
      pub fn into_column_values(self, index: usize) -> Vec<Value> {
          use Expression::*;
          match self {
              Equal(lhs, rhs) => match (*lhs, *rhs) {
                  (Column(column), Constant(value)) | (Constant(value), Column(column)) => {
                      assert_eq!(column, index, "unexpected column");
                      // NULL and NAN index lookups are for IS NULL and IS NAN.
                      // Equality shouldn't match anything, return empty vec.
                      if value.is_undefined() {
                          Vec::new()
                      } else {
                          vec![value]
                      }
                  }
                  (lhs, rhs) => panic!("unexpected expression {:?}", Equal(lhs.into(), rhs.into())),
              },
              // IS NULL and IS NAN can use index lookups.
              Is(expr, value) => match *expr {
                  Column(column) => {
                      assert_eq!(column, index, "unexpected column");
                      vec![value]
                  }
                  expr => panic!("unexpected expression {expr:?}"),
              },
              Or(lhs, rhs) => {
                  let mut values = lhs.into_column_values(index);
                  values.extend(rhs.into_column_values(index));
                  values
              }
              expr => panic!("unexpected expression {expr:?}"),
          }
      }

      /// Replaces column references with the given column.
      pub fn replace_column(self, from: usize, to: usize) -> Self {
          let xform = |expr| match expr {
              Expression::Column(i) if i == from => Expression::Column(to),
              expr => expr,
          };
          self.transform(&|e| Ok(xform(e)), &Ok).unwrap() // infallible
      }

      /// Shifts column references by the given amount.
      pub fn shift_column(self, diff: isize) -> Self {
          let xform = |expr| match expr {
              Expression::Column(i) => Expression::Column((i as isize + diff) as usize),
              expr => expr,
          };
          self.transform(&|e| Ok(xform(e)), &Ok).unwrap() // infallible
      }
  }
  ```
]
=== 总结

Type这一部分是比较简单的，没有太多的复杂的逻辑。主要是定义了一些基本的数据结构，比如表结构，列结构，表达式等。表达式是一个递归的数据结构，可以表示复杂的逻辑表达式。这一部分的代码主要是定义了这些数据结构，以及对这些数据结构的一些操作。