#import "../../lib.typ": *

== MVCC介绍
MVCC#footnote("Multi-Version Concurrency Control： https://zh.wikipedia.org/wiki/多版本并发控制")是广泛使用的并发控制机制，他为ACID事务提供快照隔离#footnote("https://jepsen.io/consistency/models/snapshot-isolation")，能实现读写并发。快照隔离级别是最高的隔离级别么?
并不是，最高的隔离级别是可串行化隔离级别，但是可串行化隔离级别会导致性能问题，所以快照隔离级别是一个折中的选择。

快照隔离级别会导致写倾斜(Write Skew)问题#footnote("https://justinjaffray.com/what-does-write-skew-look-like/")，但是这个问题在实际中并不常见。详细的讨论可以参考@write-skew。

=== MVCC的实现

ToyDB在存储层实现了MVCC，可以使用任何实现了`storage::Engine`存储引擎作为底层存储。在ToyDB中，提供了常见的事务操作：
- `begin`： 开始一个新的事务。(可以是只读事务(read only)，也可以是读写事务)
- `get`： 读取一个key的值
- `set`： 设置一个key的值
- `delete`： 删除一个key的值
- `scan`： 遍历指定范围的key/value对
- `scan_prefix`： 遍历指定前缀的key/value对
- `commit`： 提交一个事务。（保留更改，对其他事务可见）
- `rollback`： 回滚一个事务。（丢弃更改）

MVCC，顾名思义，是通过多个版本来管理事务的。版本的先后通过`Version`来界定，可以说，`Version`就是一个逻辑时间戳。通过`Version`用来标记每一个写入的`Key`，就可以在一个确定的时刻(`Version`一定的时刻)，知道一个`Key`的值是什么。

```rust
// x 表示 tombstone 值
时间(Version)
5
4  a4
3      b3      x
2
1  a1      c1  d1
   a   b   c   d   Key
```

上面就是一个例子，在`Version = 2`的时候，可以看到`a`的值是`a1`，`c`的值是`c1`，`d`的值是`d1`。在`Version = 4`的时候，`a`的值是`a4`，`b`的值是`b3`，`c`的值是`c1`。（没提到就是空值）

这里有必要说一下，上面一段话中多次提到`Key`，但是表示有不同的意思。`Key`分为存储引擎中的`Key`和事务管理(MVCC)中的`Key`枚举类。在本书后续部分，大家需要根据上下文来理解。

事务管理的`Key`枚举类的值会通过序列化成存储引擎中的`Key`来存储。这一点对于理解下面MVCC的实现非常重要。关于序列化的实现，会在
@encoding 详细说明#footnote(
  "关于序列化也可以阅读一下： " + "https://research.cs.wisc.edu/mist/SoftwareSecurityCourse/Chapters/3_5-Serialization.pdf",
)，这里只需要知道实现了`serde`的`Deserialize`和`Serialize`两个`trait`就可以通过`encode()`将一个对象序列化成`vec<u8>`，通过`decode()`把`vec<u8>`反序列化成一个对象就可以了。

另外，通过`serde`的`with = "serde_bytes"`和`borrow`可以将`Cow`类型的数据序列化成`vec<u8>`，这个在`Key`枚举类中会用到。

下面来看一下`Key`枚举类的定义。

#code-figure(
  // "toydb/src/storage/mvcc.rs",
  "Key 枚举类",
)[
```rust
  /// MVCC keys, using the KeyCode encoding which preserves the ordering and
  /// grouping of keys. Cow byte slices allow encoding borrowed values and
  /// decoding into owned values.
  /// MVCC keys, 使用 KeyCode 编码, 保留了 key 的顺序和分组.
  /// Cow 允许对 borrowed 的值进行编码, 并且解码成 owned 的值.
  #[derive(Debug, Deserialize, Serialize)]
  pub enum Key<'a> {
      /// The next available version.
      /// 下一个可以使用的 version.
      NextVersion,
      /// Active (uncommitted) transactions by version.
      /// 在给定 version 下, 活动的(未提交的)事务.
      TxnActive(Version),
      /// A snapshot of the active set at each version. Only written for
      /// versions where the active set is non-empty (excluding itself).
      /// 每个 version 下的活动集的快照. 只有在活动集非空的时候才会写入.
      TxnActiveSnapshot(Version),
      /// Keeps track of all keys written to by an active transaction (identified
      /// by its version), in case it needs to roll back.
      /// 用于跟踪所有被活动事务(通过 version 标识)写入的 key, 以防需要回滚.
      TxnWrite(
          Version,
          #[serde(with = "serde_bytes")]
          #[serde(borrow)]
          Cow<'a, [u8]>,
      ),
      /// A versioned key/value pair.
      /// 一个带有 version 的 key/value 对.
      Version(
          #[serde(with = "serde_bytes")]
          #[serde(borrow)]
          Cow<'a, [u8]>,
          Version,
      ),
      /// Unversioned non-transactional key/value pairs. These exist separately
      /// from versioned keys, i.e. the unversioned key "foo" is entirely
      /// independent of the versioned key "foo@7". These are mostly used
      /// for metadata.
      /// 非事务的 key/value 对. 这些和带有 version 的 key 是独立的.
      /// 例如, unversioned key "foo" 和 versioned key "foo@7" 是完全独立的.
      /// 这些主要用于元数据.
      Unversioned(
          #[serde(with = "serde_bytes")]
          #[serde(borrow)]
          Cow<'a, [u8]>,
      ),
  }
  ```
]

看到这里应该看的一头雾水，不过没有关系，再粗略看一下`KeyPrefix`，然后再统一解释。

#code-figure(
  // "toydb/src/storage/mvcc.rs",
  "KeyPrefix 枚举类",
)[
```rust
  /// MVCC key prefixes, for prefix scans. These must match the keys above,
  /// including the enum variant index.
  /// MVCC key 的前缀, 用于前缀扫描. 这些必须和上面的 key 匹配, 包括枚举变量的索引.
  #[derive(Debug, Deserialize, Serialize)]
  enum KeyPrefix<'a> {
      NextVersion,
      TxnActive,
      TxnActiveSnapshot,
      TxnWrite(Version),
      Version(
          #[serde(with = "serde_bytes")]
          #[serde(borrow)]
          Cow<'a, [u8]>,
      ),
      Unversioned,
  }
  ```
]

现在来理解一下`Key`和`KeyPrefix`。它们都实现了`Deserialize/Serialize`这两个trait，所以里面的枚举值就可以序列化和反序列化。换句话说，就是可以将`Key`和`KeyPrefix`中的枚举值序列化成`vec<u8>`，然后存储到存储引擎中。

`NextVersion`：顾名思义，表示的是下一个Version。当事务开始的时候，会从`NextVersion`获取下一个可用的version并且递增它。

`TxnActive`：表示的是活动中事务

`TxnActiveSnapshot`：表示的是活动事务的快照

`TxnWrite`：

`Version`：

`Unversioned`：

其实在测试用例中说明了问题。

#code-figure(
  //   "toydb/src/storage/mvcc.rs",
  "Key 与 KeyPrefix 的测试用例",
)[
```rust
  #[test_case(KeyPrefix::NextVersion, Key::NextVersion; "NextVersion")]
  #[test_case(KeyPrefix::TxnActive, Key::TxnActive(1); "TxnActive")]
  #[test_case(KeyPrefix::TxnActiveSnapshot, Key::TxnActiveSnapshot(1); "TxnActiveSnapshot")]
  #[test_case(KeyPrefix::TxnWrite(1), Key::TxnWrite(1, b"foo".as_slice().into()); "TxnWrite")]

  #[test_case(KeyPrefix::Version(b"foo".as_slice().into()), Key::Version(b"foo".as_slice().into(), 1); "Version")]

  #[test_case(KeyPrefix::Unversioned, Key::Unversioned(b"foo".as_slice().into()); "Unversioned")]
  fn key_prefix(prefix: KeyPrefix, key: Key) {
      let prefix = prefix.encode();
      let key = key.encode();
      assert_eq!(prefix, key[..prefix.len()])
  }
  ```
]

// #reference-block("Rust中的写时复制")[
//   在上面`Key`以及`KeyPrefix`枚举类中多次出现了COW类型，这里简单介绍一下COW。

//   COW（copy on wirte，写时复制）这是一个非常常见的概念。在Rust中，`Cow`是一个枚举类，有两个值，`Borrowed`和`Owned`，`Borrowed`表示借用，`Owned`表示拥有。

//   当一个`Cow`是`Borrowed`的时候，它是一个引用，当一个`Cow`是`Owned`的时候，它是一个拥有者。

//   通过`Cow`可以实现写时复制，也就是说，当一个`Cow`是`Borrowed`的时候，如果需要修改，就会复制一份，然后修改这份拷贝，这样就不会影响原来的数据。

//   看一下这段代码能简单的理解一下COW。
//   ```rust
//   use std::borrow::Cow;
//   fn process_data(input: &str, modify: bool) -> Cow<str> {
//       if modify {
//           let mut owned_string = input.to_string();
//           owned_string.push_str("(modified)");
//           Cow::Owned(owned_string)
//       } else {
//           Cow::Borrowed(input)
//       }
//   }

//   /*
//     结果为：
//     Result 1: this is a test string, Address: 0x56a76d9d3213
//     Result 2: this is a test string, Address: 0x56a76d9d3213
//     Result 3: this is a test string(modified), Address: 0x56a76f1efb80
//   */
//   fn main() {
//       let test_string = "this is a test string";
//       let result1 = process_data(test_string, false);
//       let result2 = process_data(test_string, false);
//       let result3 = process_data(test_string, true);
//       println!("Result 1: {}, Address: {:?}", result1, result1.as_ptr());
//       println!("Result 2: {}, Address: {:?}", result2, result2.as_ptr());
//       println!("Result 3: {}, Address: {:?}", result3, result3.as_ptr());
//   }
//   ```
// ]

看完了 `Key` 和 `KeyPrefix`，就来具体看一下MVCC的实现了。不过还有一个前置点是需要理解ToyDB中`MVCC`与`Transaction`的关系。

先看一下MVCC的代码。

#code-figure(
  // "toydb/src/storage/mvcc.rs",
  "MVCC",
)[
```rust
  /// An MVCC-based transactional key-value engine. It wraps an underlying storage
  /// engine that's used for raw key/value storage.
  ///
  /// While it supports any number of concurrent transactions, individual read or
  /// write operations are executed sequentially, serialized via a mutex. There
  /// are two reasons for this: the storage engine itself is not thread-safe,
  /// requiring serialized access, and the Raft state machine that manages the
  /// MVCC engine applies commands one at a time from the Raft log, which will
  /// serialize them anyway.
  /// 基于 MVCC 的事务键值引擎. 它包装了一个底层的存储引擎, 用于原始的 key/value 存储.
  /// 虽然它支持任意数量的并发事务, 但是单个读写操作是顺序执行的, 通过互斥锁串行化.
  /// 有两个原因: 存储引擎本身不是线程安全的, 需要串行访问, 以及管理 MVCC 引擎的 Raft 状态机
  /// 会从 Raft 日志中一次应用一个命令, 这样也会将它们串行化.
  pub struct MVCC<E: Engine> {
      pub engine: Arc<Mutex<E>>,
  }

  impl<E: Engine> MVCC<E> {
      /// Creates a new MVCC engine with the given storage engine.
      /// 使用给定的存储引擎创建一个新的 MVCC 引擎.
      pub fn new(engine: E) -> Self { Self { engine: Arc::new(Mutex::new(engine)) } }
      /// Begins a new read-write transaction.
      /// 开始一个新的读写事务.
      pub fn begin(&self) -> Result<Transaction<E>> { Transaction::begin(self.engine.clone()) }
      /// Begins a new read-only transaction at the latest version.
      /// 开始一个新的只读事务, 在最新的 version 下.
      pub fn begin_read_only(&self) -> Result<Transaction<E>> {
          Transaction::begin_read_only(self.engine.clone(), None)
      }
      /// Begins a new read-only transaction as of the given version.
      /// 开始一个新的只读事务, 在给定的 version 下.
      pub fn begin_as_of(&self, version: Version) -> Result<Transaction<E>> {
          Transaction::begin_read_only(self.engine.clone(), Some(version))
      }
      /// Resumes a transaction from the given transaction state.
      /// 从给定的事务状态恢复事务.
      pub fn resume(&self, state: TransactionState) -> Result<Transaction<E>> {
          Transaction::resume(self.engine.clone(), state)
      }
      /// Fetches the value of an unversioned key.
      /// 获取一个非版本化 key 的值.
      pub fn get_unversioned(&self, key: &[u8]) -> Result<Option<Vec<u8>>> {
          self.engine.lock()?.get(&Key::Unversioned(key.into()).encode())
      }
      /// Sets the value of an unversioned key.
      /// 设置一个非版本化 key 的值.
      pub fn set_unversioned(&self, key: &[u8], value: Vec<u8>) -> Result<()> {
          self.engine.lock()?.set(&Key::Unversioned(key.into()).encode(), value)
      }
      /// Returns the status of the MVCC and storage engines.
      /// 返回 MVCC 和存储引擎的状态.
      pub fn status(&self) -> Result<Status> {
          let mut engine = self.engine.lock()?;
          let versions = match engine.get(&Key::NextVersion.encode())? {
              Some(ref v) => Version::decode(v)? - 1,
              None => 0,
          };
          let active_txns = engine.scan_prefix(&KeyPrefix::TxnActive.encode()).count() as u64;
          Ok(Status { versions, active_txns, storage: engine.status()? })
      }
  }

  /// MVCC engine status.
  /// MVCC 引擎状态.
  #[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
  pub struct Status {
      /// The total number of MVCC versions (i.e. read-write transactions).
      /// MVCC 版本的总数(即读写事务).
      pub versions: u64,
      /// Number of currently active transactions.
      /// 当前活动事务的数量.
      pub active_txns: u64,
      /// The storage engine.
      /// 存储引擎.
      pub storage: super::engine::Status,
  }
  ```
]

// #reference-block("Rust中transpose")[
//   `transpose`就是帮助我们将*嵌套的结构*转换成更合适处理的一种结构。比如将`Option<Result<T,E>>`转换成`Result<Option<T>, E>`。这样就可以更方便的同时处理可能的错误（`Result`）以及可能的空值（`Option`）。

//   看一下下面的例子，可以更好的理解`transpose`的作用。
//   ```rust
//   fn fetch_data(input: Option<&str>) -> Option<Result<i32, std::num::ParseIntError>> {
//     input.map(|s| s.parse::<i32>())
//   }

//   fn main() {
//     let data = Some("123");  // 有一个字符串，可能会转换为数字

//     // 不使用 transpose
//     // 手动处理 Option<Result<i32, E>>
//     let result: Result<Option<i32>, std::num::ParseIntError> = match fetch_data(data) {
//         Some(Ok(value)) => Ok(Some(value)),    // 成功解析数字
//         Some(Err(e)) => Err(e),                // 解析时出错
//         None => Ok(None),                      // 没有数据
//     };

//     // 等价于上面的代码
//     let result = fetch_data(data).transpose();

//     // 处理result结果
//     match result {
//         Ok(Some(value)) => println!("成功解析数字: {}", value),
//         Ok(None) => println!("没有数据"),
//         Err(e) => println!("解析错误: {}", e),
//     }
//   }

//   ```

//   在ToyDB中有许多地方使用了`transpose`，这样可以更方便的处理`Option<Result<T, E>>`这种结构。

//   比如下面这段代码，我感觉非常的优雅：
//   ```rust
//     // scan.next() 返回的是 Option<Result<(key, value), E>>
//     // 为了方便处理, 使用了 transpose(), 将其转换为 Result<Option<(key, value)>, E>

//     // 如果 scan.next() 返回 None, 意味着迭代结束, transpose() 会返回 Ok(None)
//     // 就会跳出循环

//     // 如果 scan.next() 返回 Some(Err(e)), transpose() 会返回 Err(e)
//     // 并立即中断循环, 错误通过 ? 操作符进行传播

//     // 如果 scan.next() 返回 Some(Ok((key, value))), transpose() 会返回 Ok(Some((key, value)))
//     // 就会向下处理
//     while let Some((key, value)) = scan.next().transpose()? {
//         match Key::decode(&key)? {
//             Key::Version(_, version) => {
//                 // ...
//             }
//             key => return errdata!("expected Key::Version got {key:?}"),
//         };
//     }
//   ```
// ]

在代码中可以看到，MVCC中更多的对Transaction以及存储引擎的一层封装。在一个事务想要开启的时候，先通过`MVCC`来开启一个（读写/只读）事务，之后关于事务的处理就不再属于`MVCC`来管理，转而到了稍后会讲到的`Trancation`中。

当事务开始的时候，从`Key::NextVersion`获取下一个可用的version并且递增它，然后通过`Key::TxnActive(version)`将自身记录为活动中的事务。它还会将当前活动的事务做一个快照，其中包含了事务开始的时候其他所有活动事务的version，并且将起另存为`Key::TxnActiveSnapshot(id)`。

key/value保存为`Key::Version(key, version)`的形式，其中`key`是用户提供的key，`version`是事务的版本。事务的key/value的可见性如下：
- 对于给定的key，从当前事务的版本开始对`Key::Version(key, version)`进行反向的扫描。
- 如果一个版本位于活动集(active set)中的时候，跳过这个版本。
- 返回第一个匹配记录（如果有的话），这个记录可能是`Some(value)`或者`None`。

写入key/value的时候，事务首先要扫描其不可见的`Key::Version(key, version)`来检查是否存在任何冲突。如果有找到一个，那么需要返回序列化错误，调用者必须重试这个事务。如果没有找到，事务就会写入新记录，并且以`Key::TxnWrite(version, key)`的形式来跟踪更改，以防必须回滚的情况。

当事务提交的时候，就只需要删除其`Txn::Active(id)`记录，使其更改对其他后续的事务可见就可以了。如果事务回滚，就遍历所有的`Key::TxnWrite(id, key)`记录，并删除写入的key/value值，最后删除`Txn::Active(id)`记录就可以了。

这个方案可以保证ACID事务的快照隔离：
提交是原子的，每一个事务在开始的时候，看到的都是key/value存储的一致性快照，并且任何写入冲突都会导致序列化冲突，必须重试。

为了实现时间穿梭查询，只读事务只需加载过去事务的`Key::TxnActiveShapshot`记录就可以了，可见性规则和普通事务是一样的。

=== MVCC在ToyDB中的取舍
+ 旧的MVCC版本永远不会被删除，会导致存储空间的浪费。但是这简化了实现，也允许完整的数据历史记录。
+ 事务id会在64位后溢出，没有做处理。
