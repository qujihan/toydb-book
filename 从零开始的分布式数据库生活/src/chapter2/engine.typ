#import "../../lib.typ": *
== Engine Trait
在存储引擎中，每一对 KV 都是以字母序来存储的字节序列（byte slice）。其中Key是有序的，这样就可以进行高效的范围查询。范围查询在一些场景下非常有用，比如在执行一个扫描表的SQL的时候（所有的行都是以相同的key前缀）。Key应该使用KeyCode进行编码（接下来会讲到）。在写入以后，数据并没有持久化，还需要调用flush()保证数据持久化。

在ToyDB中，即使是读操作，也只支持单线程，这是因为所有方法都包含一个存储引擎的可变引用。无论是raft的日志运用到状态机还是对文件的读取操作，都是只能顺序访问的。

在ToyDB中，实现了一个基于BitCask的，一个基于标准库BTree的存储引擎。

每一个可以被ToyDB使用的存储引擎都需要实现`storage::Engine`这个trait。下面看一下这个trait。

#code-figure(
  // "toydb/src/storage/engine.rs",
  "strong::Engine",
)[
  ```rust
  /// 带有 Self: Sized 是为了无法使用trait object(比如Box<dyn Engine>)
  /// 但是也提供了一个scan_dyn()方法来返回一个trait object
  pub trait Engine: Send {
      /// scan()返回的迭代器
      type ScanIterator<'a>: ScanIterator + 'a
      where
          Self: Sized + 'a;
      /// 删除一个key, 如果不存在就什么都不发生
      fn delete(&mut self, key: &[u8]) -> Result<()>;
      /// 将缓冲区的内容写出到存储介质中
      fn flush(&mut self) -> Result<()>;
      fn get(&mut self, key: &[u8]) -> Result<Option<Vec<u8>>>;
      /// 遍历指定范围的key/value对
      fn scan(&mut self, range: impl std::ops::RangeBounds<Vec<u8>>) -> Self::ScanIterator<'_>
      where
          Self: Sized;
      /// 与scan()类似, 能被trait object使用. 由于使用了dynamic dispatch, 所以性能会有所下降
      fn scan_dyn(
          &mut self,
          range: (std::ops::Bound<Vec<u8>>, std::ops::Bound<Vec<u8>>),
      ) -> Box<dyn ScanIterator + '_>;
      /// 遍历指定前缀的key/value对
      fn scan_prefix(&mut self, prefix: &[u8]) -> Self::ScanIterator<'_>
      where
          Self: Sized,
      {
          self.scan(keycode::prefix_range(prefix))
      }
      /// 设置一个key/value对, 如果存在则替换
      fn set(&mut self, key: &[u8], value: Vec<u8>) -> Result<()>;
      /// 获取存储引擎的状态
      fn status(&mut self) -> Result<Status>;
  }
  ```
]<engine>

其中的`get`，`set`以及`delete`只是简单的读取以及写入key/value对，并且通过`flush`可以确保将缓冲区的内容写出到存储介质中(通过`fsync`系统调用等方式)。`scan`按照顺序迭代指定的KV对范围。这个对一些高级功能(SQL表扫描等)至关重要。并且暗含了以下一些语义：
- 为了提高性能，存储的数据应该是有序的。
- key应该保留字节编码，这样才能实现范围扫描。

对于存储引擎而已，并不关心`key`是什么，但是为了方便上层的调用，提供了一个称为`KeyCode`的order-preserving编码，具体可以在 @encoding 看到。

此外在上面的代码中还需要注意两个东西，一个是`ScanIterator`，一个是`Status`。`ScanIterator`是一个迭代器，用于遍历存储引擎中的KV对。`Status`是用于获取存储引擎的状态，比如存储引擎的大小，垃圾量等。

现在简单看一下`Status`。

#code-figure(
  // "toydb/src/storage/engine.rs",
  "Status",
)[
  ```rust
  #[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
  pub struct Status {
      /// The name of the storage engine.
      /// 存储引擎的名字
      pub name: String,
      /// The number of live keys in the engine.
      /// 存储引擎中的活跃key的数量
      pub keys: u64,
      /// The logical size of live key/value pairs.
      /// 存储引擎中的活跃key/value对的逻辑大小
      pub size: u64,
      /// The on-disk size of all data, live and garbage.
      /// 所有数据的磁盘大小, 包括活跃和垃圾数据
      pub total_disk_size: u64,
      /// The on-disk size of live data.
      /// 活跃数据的磁盘大小
      pub live_disk_size: u64,
      /// The on-disk size of garbage data.
      /// 垃圾数据的磁盘大小
      pub garbage_disk_size: u64,
  }

  impl Status {
      pub fn garbage_percent(&self) -> f64 {
          if self.total_disk_size == 0 {
              return 0.0;
          }
          self.garbage_disk_size as f64 / self.total_disk_size as f64 * 100.0
      }
  }
  ```
]

简简单单几个属性，以及定义了一个计算垃圾比例的方法。这个比例可以用来判断是否需要进行压缩。

再看一下`ScanIterator`。

#code-figure(
  // "toydb/src/storage/engine.rs", 
  "ScanIterator"
  )[
  ```rust
  /// A scan iterator, with a blanket implementation (in lieu of trait aliases).
  pub trait ScanIterator: DoubleEndedIterator<Item = Result<(Vec<u8>, Vec<u8>)>> {}

  impl<I: DoubleEndedIterator<Item = Result<(Vec<u8>, Vec<u8>)>>> ScanIterator for I {}
  ```
]

这里定义了一个`trait`，用于遍历存储引擎中的KV对 (@engine 中`Scan*`所用)。这个`trait`指定了`Item`(`Item`就是迭代项)类型为`Result<(Vec<u8>, Vec<u8>)>`，其中`Vec<u8>, Vec<u8>`分别是key，value。另外这个`trait`还需要组合`DoubleEndedIterator`这个`trait`。

另外`ScanIterator`没有定义任何额外的方法，这个实现是空的，这种方式称为 blanket implementation（通用实现），这个允许我们为一大类类型提供一个统一的实现。

