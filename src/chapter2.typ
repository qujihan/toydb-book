#import "../typst-book-template/book.typ": *
#let path-prefix = figure-root-path + "src/pics/"

= 存储引擎
#code(
  "tree src/storage",
  "存储引擎的代码结构",
)[
  ```zsh
  src/storage
  ├── bitcask.rs # 基于BitCask实现的存储引擎
  ├── engine.rs  # 存储引擎的trait
  ├── memory.rs  # 基于标准库中的BTree实现的存储引擎
  ├── mod.rs
  ├── mvcc.rs    # 在存储引擎之上实现MVCC事务
  └── testscripts
      └── ....   # 测试文件
  ```
]

ToyDB使用一个可替换的KV存储引擎, 通过storage_sql和storage_raft选项分别配置SQL和Raft存储引擎. 关于更高层的SQL存储引擎将在SQL部分单独讨论.

== 编码以及存储引擎

=== 存储引擎trait

在存储引擎中, 每一对 KV 都是以字母序来存储的字节序列(byte slice). 其中Key是有序的, 这样就可以进行高效的范围查询. 范围查询在一些场景下非常有用, 比如在执行一个扫描表的SQL的时候(所有的行都是以相同的key前缀). Key应该使用KeyCode进行编码(接下来会讲到). 在写入以后, 数据并没有持久化, 还需要调用flush()保证数据持久化.

在ToyDB中, 即使是读操作, 也只支持单线程, 这是因为所有方法都包含一个存储引擎的可变引用. 无论是raft的日志运用到状态机还是对文件的读取操作, 都是只能顺序访问的.

在ToyDB中, 实现了一个基于BitCask的, 一个基于标准库BTree的存储引擎.

每一个可以被ToyDB使用的存储引擎都需要实现`storage::Engine`这个trait. 下面看一下这个trait.

#code(
  "toydb/src/storage/engine.rs",
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
]

其中的`get`, `set`以及`delete`只是简单的读取以及写入key/value对, 并且通过`flush`可以确保将缓冲区的内容写出到存储介质中(通过`fsync`系统调用等方式). `scan`按照顺序迭代指定的KV对范围. 这个对一些高级功能(SQL表扫描等)至关重要. 并且暗含了以下一些语义:
- 为了提高性能, 存储的数据应该是有序的.
- key应该保留字节编码, 这样才能实现范围扫描.

对于存储引擎而已, 并不关心`key`是什么, 但是为了方便上层的调用, 提供了一个称为`KeyCode`的order-preserving#footnote("TODO")编码.

// TODO 没看懂这里啥玩意这是


ToyDB使用的存储引擎是BitCask#footnote("https://riak.com/assets/bitcask-intro.pdf")的变种, 在写入的时候, 先写入到log文件中, 索引会在内存中维护key与文件位置的关系. 当垃圾量(包含替换以及删除的key)大于20%的时候, 将在内存中的key写入到新的log文件中, 替换掉老的log文件.


== ToyDB中使用的BitCask

BitCask(可以参考@bitcask)是一个非常简单的基于Log的KV引擎. BitCask将KV对写入到一个只能追加写的Log文件中. 并在内存中维护一个Key到文件位置的索引.
上面这段话存在的隐藏的语义就是:
- BitCask要求所有的Key必须能存放在内存中
- BitCask在启动的时候需要扫描Log文件来构建索引

另外删除文件的时候并不是真正的删除, 而是写入一个墓碑值(tombstone value), 这样在读取的时候就会认为这个Key已经被删除了.

Log的压缩就是将内存中的Key重新写入到一个新的Log文件中, 这样就可以删除掉老的Log文件. 这个过程会导致写放大问题, 但是这个过程是可以控制的, 比如可以设置一个阈值, 当超过这个阈值的时候才进行压缩.


下面来看看ToyDB中的Bitcask是如何实现的.

#code(
  "toydb/src/storage/bitcask.rs",
  "bitcask",
)[
  ```rust
  struct Log {
      /// Path to the log file.
      /// 日志文件的路径
      path: PathBuf,
      /// The opened file containing the log.
      /// 包含日志的打开文件
      file: std::fs::File,
  }

  /// Maps keys to a value position and length in the log file.
  /// 将key映射到日志文件中的value位置和长度
  type KeyDir = std::collections::BTreeMap<Vec<u8>, (u64, u32)>;

  pub struct BitCask {
      /// The active append-only log file.
      /// 当前的只追加写的日志文件
      log: Log,
      /// Maps keys to a value position and length in the log file.
      /// 将key映射到日志文件中的value位置和长度
      keydir: KeyDir,
  }
  ```
]<bitcask_code>


在ToyDB中, `BitCask` 中包含一个管理内存中索引文件的数据结构 `keydir` 以及一个用来写Log的文件 `log`.

其中 `keydir` 是一个BTree, key是一个Vec<u8>, value是一个元组(u64, u32), 其中u64是value在Log文件中的位置, u32是value的长度. 这个结构是有序的, 这样就可以进行范围查询.

再来看 `log`, 它包含了一个文件路径 `path` 以及一个文件句柄 `file`. 这个文件是只追加写的, 这样就可以保证写入的顺序是正确的.

下面先看 `log` 实现部分, 再来回看 `BitCask` 的部分.

=== Log实现

每一个log entry包含四个部分:
- Key 的长度, 大端u32
- Value 的长度, 大端i32, -1 表示墓碑值
- Key 的字节序列(最大 2GB)
- Value 的字节序列(最大 2GB)

在Log中, `new` 比较简单, 是打开一个log文件, 当不存在的时候就创建这个文件. 并且在使用过程中一直使用的排它锁, 这样就可以保证只有一个线程在写入.


#code(
  "toydb/src/storage/bitcask.rs",
  "new",
)[
  ```rust
  fn new(path: PathBuf) -> Result<Self> {
      if let Some(dir) = path.parent() {
          std::fs::create_dir_all(dir)?
      }
      let file = std::fs::OpenOptions::new()
          .read(true)
          .write(true)
          .create(true)
          .truncate(false)
          .open(&path)?;
      file.try_lock_exclusive()?;
      Ok(Self { path, file })
  }
  ```
]


`read_value`,`write_value` 这两个函数也比较简单, 用于读取value以及写入KV对.

#code(
  "toydb/src/storage/bitcask.rs",
  "read_value",
)[
  ```rust
  /// 从file的value_pos位置读取value_len长度的数据
  fn read_value(&mut self, value_pos: u64, value_len: u32) -> Result<Vec<u8>> {
      let mut value = vec![0; value_len as usize];
      self.file.seek(SeekFrom::Start(value_pos))?;
      self.file.read_exact(&mut value)?;
      Ok(value)
  }
  ```
]

#code(
  "toydb/src/storage/bitcask.rs",
  "write_value",
)[
  ```rust
  /// 写入key/value对, 返回写入的位置和长度
  /// 墓碑值使用 None Value
  fn write_entry(&mut self, key: &[u8], value: Option<&[u8]>) -> Result<(u64, u32)> {
      let key_len = key.len() as u32;
      // map_or 是 Option类型的方法, 用于在 Option 为 Some 以及 None 时执行不同的操作
      let value_len = value.map_or(0, |v| v.len() as u32);
      let value_len_or_tombstone = value.map_or(-1, |v| v.len() as i32);
      // 这里 4 + 4 就是 key_len(u32) 和 value_len_or_tombstone(u32) 的长度
      let len = 4 + 4 + key_len + value_len;

      let pos = self.file.seek(SeekFrom::End(0))?;
      // BufWriter 是一个带有缓冲的写操作, 可以减少实际IO操作的次数
      let mut w = BufWriter::with_capacity(len as usize, &mut self.file);
      w.write_all(&key_len.to_be_bytes())?;
      w.write_all(&value_len_or_tombstone.to_be_bytes())?;
      w.write_all(key)?;
      if let Some(value) = value {
          w.write_all(value)?;
      }
      w.flush()?;

      Ok((pos, len))
  }
  ```
]

`build_keydir` 就比较复杂了, 用来构建索引(ToyDB只有在重启的时候才会构建).

#code(
  "toydb/src/storage/bitcask.rs",
  "build_keydir",
)[
  ```rust
  /// Builds a keydir by scanning the log file. If an incomplete entry is
  /// encountered, it is assumed to be caused by an incomplete write operation
  /// and the remainder of the file is truncated.
  /// 通过扫描log文件来构建一个keydir. 如果遇到不完整的条目, 就会假设是因为不完整的写操作
  /// 并且截断文件.
  fn build_keydir(&mut self) -> Result<KeyDir> {
      let mut len_buf = [0u8; 4];
      let mut keydir = KeyDir::new();
      let file_len = self.file.metadata()?.len();
      let mut r = BufReader::new(&mut self.file);
      let mut pos = r.seek(SeekFrom::Start(0))?;

      while pos < file_len {
          // Read the next entry from the file, returning the key, value
          // position, and value length or None for tombstones.
          // 读取一条新的条目, 返回key, value位置, 以及value长度或者墓碑值(None)
          let result = || -> std::result::Result<(Vec<u8>, u64, Option<u32>), std::io::Error> {
              // r 在当前文件指针位置读取数据到 len_buf 中
              // 读取完成以后文件指针会自动向后移动 len_buf.len() 的大小
              r.read_exact(&mut len_buf)?;
              let key_len = u32::from_be_bytes(len_buf);
              r.read_exact(&mut len_buf)?;
              let value_len_or_tombstone = match i32::from_be_bytes(len_buf) {
                  l if l >= 0 => Some(l as u32),
                  _ => None, // -1 for tombstones
              };
              let value_pos = pos + 4 + 4 + key_len as u64;

              let mut key = vec![0; key_len as usize];
              r.read_exact(&mut key)?;

              if let Some(value_len) = value_len_or_tombstone {
                  if value_pos + value_len as u64 > file_len {
                      // 这里就是遇到了不完整的条目
                      return Err(std::io::Error::new(
                          std::io::ErrorKind::UnexpectedEof,
                          "value extends beyond end of file",
                      ));
                  }
                  // 在当前文件指针位置移动 value_len 的大小
                  // 使用 seek_relative 而不是 seek 是为了避免丢弃缓冲区
                  //
                  // seek 是把文件指针立刻移动到某个位置, 旧的缓冲区的数据可能和新的位置不匹配
                  // 所以缓冲失效会被丢弃
                  r.seek_relative(value_len as i64)?; // avoids discarding buffer
              }

              Ok((key, value_pos, value_len_or_tombstone))
          }();

          match result {
              // Populate the keydir with the entry, or remove it on tombstones.
              // 填充 keydir, 或者在墓碑值的时候删除
              Ok((key, value_pos, Some(value_len))) => {
                  keydir.insert(key, (value_pos, value_len));
                  pos = value_pos + value_len as u64;
              }
              Ok((key, value_pos, None)) => {
                  keydir.remove(&key);
                  pos = value_pos;
              }
              // If an incomplete entry was found at the end of the file, assume an
              // incomplete write and truncate the file.
              // 这里就是遇到了不完整的条目
              Err(err) if err.kind() == std::io::ErrorKind::UnexpectedEof => {
                  log::error!("Found incomplete entry at offset {}, truncating file", pos);
                  self.file.set_len(pos)?;
                  break;
              }
              Err(err) => return Err(err.into()),
          }
      }
      Ok(keydir)
  }
  ```
]
=== BitCask实现

在知道了 `log` 是如何实现的以后, 就可以更好的理解BitCask的实现了. 在@bitcask_code 中可以看到, `BitCask` 中包含了一个 `log` 以及一个 `keydir`. `log` 用来写入KV对, `keydir` 用来维护内存中的索引.

下面先看一下 `BitCask` 中的一些周边函数, 然后再看一下如何实现 `Engine` 这个trait.


下面展示的两个函数是为了
#code(
  "toydb/src/storage/bitcask.rs",
  "impl BitCask",
)[
  ```rust
    /// Opens or creates a BitCask database in the given file.
    /// 通过 path 打开或者创建一个 BitCask 数据库
    pub fn new(path: PathBuf) -> Result<Self> {
        // 这里非常简单, 就是调用前面实现的 Log::new
        log::info!("Opening database {}", path.display());
        let mut log = Log::new(path.clone())?;
        let keydir = log.build_keydir()?;
        log::info!("Indexed {} live keys in {}", keydir.len(), path.display());
        Ok(Self { log, keydir })
    }

    /// Opens a BitCask database, and automatically compacts it if the amount
    /// of garbage exceeds the given ratio and byte size when opened.
    /// 打开一个 BitCask 数据库, 如果打开的时候垃圾的比例和字节大小超过给定的阈值, 就会自动压缩
    pub fn new_compact(
        path: PathBuf,
        garbage_min_fraction: f64,
        garbage_min_bytes: u64,
    ) -> Result<Self> {
        let mut s = Self::new(path)?;

        let status = s.status()?;
        if Self::should_compact(
            status.garbage_disk_size,
            status.total_disk_size,
            garbage_min_fraction,
            garbage_min_bytes,
        ) {
            log::info!(
                "Compacting {} to remove {:.0}% garbage ({} MB out of {} MB)",
                s.log.path.display(),
                status.garbage_percent(),
                status.garbage_disk_size / 1024 / 1024,
                status.total_disk_size / 1024 / 1024
            );
            s.compact()?;
            log::info!(
                "Compacted {} to size {} MB",
                s.log.path.display(),
                (status.total_disk_size - status.garbage_disk_size) / 1024 / 1024
            );
        }

        Ok(s)
    }

    /// Returns true if the log file should be compacted.
    fn should_compact(
        garbage_size: u64,
        total_size: u64,
        min_fraction: f64,
        min_bytes: u64,
    ) -> bool {
        let garbage_fraction = garbage_size as f64 / total_size as f64;
        garbage_size > 0 && garbage_size >= min_bytes && garbage_fraction >= min_fraction
    }
  ```
]




=== ToyDB中BitCask的取舍
在ToyDB中, BitCask的实现做了相当程度的简化:
+ ToyDB没有使用固定大小的日志文件, 而是使用了任意大小的仅追加写的日志文件. 这会增加压缩量, 因为每次压缩的时候都会重写整个日志文件, 并且也可能会超过文件系统的文件大小限制.
+ 压缩的时候会阻塞所有的读以及写操作, 这问题不大, 因为ToyDB只会在重启的时候压缩, 并且文件应该也比较小.
+ 没有hint文件, 因为ToyDB的value预估都比较小, hint文件的作用不大(其大小与合并的Log文件差不多大).
+ 每一条记录没有timestamps以及checksums
+ BitCask需要key的集合在内存中, 而且启动的时候需要扫描log文件来构建索引.
+ 与LSMTree不同, 单个文件的BitCask需要在压缩的过程中重写整个数据集, 这会导致显著的写放大问题.
+ ToyDB没有使用任何压缩, 比如可变长度的整数.

== MVCC事务
MVCC#footnote("Multi-Version Concurrency Control: https://zh.wikipedia.org/wiki/多版本并发控制")是一种比较简单的并发控制机制, 他为ACID事务提供快照隔离#footnote("https://jepsen.io/consistency/models/snapshot-isolation"), 从而无须锁就能实现写与读的冲突. 它还可以对所有数据进行版本控制, 允许查询历史的数据.

ToyDB在存储层实现了MVCC, 可以使用任何实现了`storage::Engine`这个trait的存储引擎. 使用`begin`开始一个新的事务, 这个事务提供常见的kv操作, 比如 `get`, `set`, `delete`等. 事务可以通过`commit`提交(保留更改且对其他事务可见), 也可以通过`rollback`回滚(丢弃修改).

当事务开始的时候, 从`Key::NextVersion`获取下一个可用的version并且递增它, 然后通过`Key::TxnActive(version)`将自身记录为活动中的事务. 它还会将当前活动的事务做一个快照, 其中包含了事务开始的时候其他所有活动事务的version, 并且将起另存为`Key::TxnActiveSnapshot(id)`.

key/value保存为`Key::Version(key, version)`的形式, 其中`key`是用户提供的key, `version`是事务的版本.事务的key/value的可见性如下:
- 对于给定的key, 从当前事务的版本开始对`Key::Version(key, version)`进行反向的扫描.
- 如果一个版本位于活动集(active set)中的时候, 跳过这个版本.
- 返回第一个匹配记录(如果有的话), 这个记录可能是`Some(value)`或者`None`.

写入key/value的时候, 事务首先要扫描其不可见的`Key::Version(key, version)`来检查是否存在任何冲突. 如果有找到一个, 那么需要返回序列化错误, 调用者必须重试这个事务. 如果没有找到, 事务就会写入新记录, 并且以`Key::TxnWrite(version, key)`的形式来跟踪更改, 以防必须回滚的情况.

当事务提交的时候, 就只需要删除其`Txn::Active(id)`记录, 使其更改对其他后续的事务可见就可以了. 如果事务回滚, 就遍历所有的`Key::TxnWrite(id, key)`记录, 并删除写入的key/value值, 最后删除`Txn::Active(id)`记录就可以了.

这个方案可以保证ACID事务的快照隔离: 提交是原子的, 每一个事务在开始的时候, 看到的都是key/value存储的一致性快照, 并且任何写入冲突都会导致序列化冲突, 必须重试.

为了实现时间穿梭查询, 只读事务只需加载过去事务的`Key::TxnActiveShapshot`记录就可以了, 可见性规则和普通事务是一样的.

=== MVCC在ToyDB中的实现

=== MVCC在ToyDB中的取舍
+ 只是实现了快照隔离级别, 并没有实现可序列化隔离级别. 会导致写倾斜(write skew)问题#footnote("https://justinjaffray.com/what-does-write-skew-look-like/").
+ 旧的MVCC版本永远不会被删除, 会导致存储空间的浪费. 但是这简化了实现, 也允许完整的数据历史记录.
+ 事务id会在64位后溢出, 没有做处理.


== 总结