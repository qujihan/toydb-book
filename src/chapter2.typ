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

ToyDB使用一个可替换的KV存储引擎，通过storage_sql和storage_raft选项分别配置SQL和Raft存储引擎。关于更高层的SQL存储引擎将在SQL部分单独讨论。

== 编码以及存储引擎

=== 存储引擎trait

在存储引擎中，每一对 KV 都是以字母序来存储的字节序列（byte slice）。其中Key是有序的，这样就可以进行高效的范围查询。范围查询在一些场景下非常有用，比如在执行一个扫描表的SQL的时候（所有的行都是以相同的key前缀）。Key应该使用KeyCode进行编码（接下来会讲到）。在写入以后，数据并没有持久化，还需要调用flush()保证数据持久化。

在ToyDB中，即使是读操作，也只支持单线程，这是因为所有方法都包含一个存储引擎的可变引用。无论是raft的日志运用到状态机还是对文件的读取操作，都是只能顺序访问的。

在ToyDB中，实现了一个基于BitCask的，一个基于标准库BTree的存储引擎。

每一个可以被ToyDB使用的存储引擎都需要实现`storage::Engine`这个trait。下面看一下这个trait。

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
]<engine>

其中的`get`，`set`以及`delete`只是简单的读取以及写入key/value对，并且通过`flush`可以确保将缓冲区的内容写出到存储介质中(通过`fsync`系统调用等方式)。`scan`按照顺序迭代指定的KV对范围。这个对一些高级功能(SQL表扫描等)至关重要。并且暗含了以下一些语义：
- 为了提高性能，存储的数据应该是有序的。
- key应该保留字节编码，这样才能实现范围扫描。

对于存储引擎而已，并不关心`key`是什么，但是为了方便上层的调用，提供了一个称为`KeyCode`的order-preserving编码，具体可以在 @encoding 看到。

此外在上面的代码中还需要注意两个东西，一个是`ScanIterator`，一个是`Status`。`ScanIterator`是一个迭代器，用于遍历存储引擎中的KV对。`Status`是用于获取存储引擎的状态，比如存储引擎的大小，垃圾量等。

现在简单看一下`Status`。

#code(
  "toydb/src/storage/engine.rs",
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

#code("toydb/src/storage/engine.rs", "ScanIterator")[
  ```rust
  /// A scan iterator, with a blanket implementation (in lieu of trait aliases).
  pub trait ScanIterator: DoubleEndedIterator<Item = Result<(Vec<u8>, Vec<u8>)>> {}

  impl<I: DoubleEndedIterator<Item = Result<(Vec<u8>, Vec<u8>)>>> ScanIterator for I {}
  ```
]

这里定义了一个`trait`，用于遍历存储引擎中的KV对 (@engine 中`Scan*`所用)。这个`trait`指定了`Item`(`Item`就是迭代项)类型为`Result<(Vec<u8>, Vec<u8>)>`，其中`Vec<u8>, Vec<u8>`分别是key，value。另外这个`trait`还需要组合`DoubleEndedIterator`这个`trait`。

另外`ScanIterator`没有定义任何额外的方法，这个实现是空的，这种方式称为 blanket implementation（通用实现），这个允许我们为一大类类型提供一个统一的实现。

== ToyDB中的BitCask
ToyDB使用的可持久化的存储引擎是BitCask(参考@bitcask)的*变种*。简单来说，就是在写入的时候，先写入到只能追加写的log文件中，然后在内存中维护一个索引，索引内容为 (key -> 文件位置以及长度)。

当垃圾量(包含替换以及删除的key)大于一定阈值的时候，将在内存中的key写入到新的log文件中，然后替换老的log文件。替换的过程被称为压缩，会导致写放大问题，但是可以通过控制阈值来减小影响。

通过上面的描述，可以分析出几个语义：
- BitCask要求所有的Key必须能存放在内存中。
- BitCask在启动的时候需要扫描Log文件来构建索引。
- 删除文件的时候并不是真正的删除。
  - 实际上是写入一个墓碑值(tombstone value)，读取到墓碑值就认为是删除了。

下面先看一下ToyDB的宏观架构，再自底向上的看一下实现过程。
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


在ToyDB中，`BitCask`中包含一个管理内存中索引文件的数据结构`keydir`以及一个用来写Log的文件`log`。

其中`keydir`是一个BTree，key是一个Vec<u8>，value是一个元组(u64, u32)，其中u64是value在Log文件中的位置，u32是value的长度。这个结构是有序的，这样就可以进行范围查询。

再来看`log`，它包含了一个文件路径`path`以及一个文件句柄`file`。这个文件是只追加写的，这样就可以保证写入的顺序是正确的。

下面先看`log`实现部分，再来回看`BitCask`的部分。

=== Log实现
每一个log entry包含四个部分：
- Key 的长度，大端u32
- Value 的长度，大端i32，-1 表示墓碑值
- Key 的字节序列(最大 2GB)
- Value 的字节序列(最大 2GB)

在Log中，`new`比较简单，是打开一个log文件，当不存在的时候就创建这个文件。并且在使用过程中一直使用的排它锁，这样就可以保证只有一个线程在写入。

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


`read_value`，`write_value`这两个函数也比较简单，用于读取value以及写入KV对。

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

`build_keydir`就比较复杂了，用来构建索引(ToyDB只有在重启的时候才会构建)。

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

在知道了`log`是如何实现的以后，就可以更好的理解BitCask的实现了。回忆一下，@bitcask_code 中，`BitCask`中包含了一个`log`以及一个`keydir`。`log`用来写入KV对，`keydir`用来维护内存中的索引。

下面先看一下`BitCask`中的一些周边函数，然后再看一下如何实现`Engine`这个trait。

先来看看`BitCask`的构造函数以及析构函数，`new`和`new_compact`。这个两个函数的区别就是`new_compact`会在打开的时候自动压缩。关于析构函数，会在Drop的时候尝试flush文件。

#code("toydb/src/storage/bitcask.rs", "impl Bitcask")[
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
  /// 如果日志文件应该被压缩, 就返回 true
  fn should_compact(
      garbage_size: u64,
      total_size: u64,
      min_fraction: f64,
      min_bytes: u64,
  ) -> bool {
      let garbage_fraction = garbage_size as f64 / total_size as f64;
      garbage_size > 0 && garbage_size >= min_bytes && garbage_fraction >= min_fraction
  }

  /// Attempt to flush the file when the database is closed.
  /// 在 Drop 的时候尝试 flush 文件
  impl Drop for BitCask {
    fn drop(&mut self) {
        if let Err(error) = self.flush() {
            log::error!("failed to flush file: {}", error)
        }
    }
  }
  ```
]

上面几个函数比较简单，下面看一下在压缩的时候会使用的函数`compact`以及`write_log`。

#code("toydb/src/storage/bitcask.rs", "compact / write_log")[
  ```rust
  impl BitCask {
      /// Compacts the current log file by writing out a new log file containing
      /// only live keys and replacing the current file with it.
      /// 压缩当前的日志文件, 写出一个新的日志文件, 只包含活跃的 key, 并且用它替换当前的文件
      pub fn compact(&mut self) -> Result<()> {
          let mut tmp_path = self.log.path.clone();
          tmp_path.set_extension("new");
          let (mut new_log, new_keydir) = self.write_log(tmp_path)?;

          std::fs::rename(&new_log.path, &self.log.path)?;
          new_log.path = self.log.path.clone();

          self.log = new_log;
          self.keydir = new_keydir;
          Ok(())
      }

      /// Writes out a new log file with the live entries of the current log file
      /// and returns it along with its keydir. Entries are written in key order.
      /// 写出一个新的日志文件, 包含当前日志文件中的活跃条目, 并且返回它以及它的 keydir.
      fn write_log(&mut self, path: PathBuf) -> Result<(Log, KeyDir)> {
          let mut new_keydir = KeyDir::new();
          let mut new_log = Log::new(path)?;
          new_log.file.set_len(0)?; // truncate file if it exists
          for (key, (value_pos, value_len)) in self.keydir.iter() {
              let value = self.log.read_value(*value_pos, *value_len)?;
              let (pos, len) = new_log.write_entry(key, Some(&value))?;
              new_keydir.insert(key.clone(), (pos + len as u64 - *value_len as u64, *value_len));
          }
          Ok((new_log, new_keydir))
      }
  }
  ```
]

这里也还是比较简单的，`write_log`函数会遍历keydir，将活跃的key/value对写入到新的log文件中。`compact`函数会调用`write_log`获取新的log文件，最后将新的log文件替换掉老的log文件。


最后我们看一下 Bitcask 对`Engine`这个trait的实现。

#code("", "")[
  ```rust
  impl Engine for BitCask {
      type ScanIterator<'a> = ScanIterator<'a>;

      fn delete(&mut self, key: &[u8]) -> Result<()> {
          self.log.write_entry(key, None)?;
          self.keydir.remove(key);
          Ok(())
      }

      fn flush(&mut self) -> Result<()> {
          // Don't fsync in tests, to speed them up. We disable this here, instead
          // of setting raft::Log::fsync = false in tests, because we want to
          // assert that the Raft log flushes to disk even if the flush is a noop.
          #[cfg(not(test))]
          self.log.file.sync_all()?;
          Ok(())
      }

      fn get(&mut self, key: &[u8]) -> Result<Option<Vec<u8>>> {
          if let Some((value_pos, value_len)) = self.keydir.get(key) {
              Ok(Some(self.log.read_value(*value_pos, *value_len)?))
          } else {
              Ok(None)
          }
      }

      fn scan(&mut self, range: impl std::ops::RangeBounds<Vec<u8>>) -> Self::ScanIterator<'_> {
          ScanIterator { inner: self.keydir.range(range), log: &mut self.log }
      }

      fn scan_dyn(
          &mut self,
          range: (std::ops::Bound<Vec<u8>>, std::ops::Bound<Vec<u8>>),
      ) -> Box<dyn super::ScanIterator + '_> {
          Box::new(self.scan(range))
      }

      fn set(&mut self, key: &[u8], value: Vec<u8>) -> Result<()> {
          let (pos, len) = self.log.write_entry(key, Some(&*value))?;
          let value_len = value.len() as u32;
          self.keydir.insert(key.to_vec(), (pos + len as u64 - value_len as u64, value_len));
          Ok(())
      }

      fn status(&mut self) -> Result<Status> {
          let keys = self.keydir.len() as u64;
          let size = self
              .keydir
              .iter()
              .fold(0, |size, (key, (_, value_len))| size + key.len() as u64 + *value_len as u64);
          let total_disk_size = self.log.file.metadata()?.len();
          // 8 * keys: key 是 u64, 所以是 8 * key的数量
          let live_disk_size = size + 8 * keys; // account for length prefixes
          let garbage_disk_size = total_disk_size - live_disk_size;
          Ok(Status {
              name: "bitcask".to_string(),
              keys,
              size,
              total_disk_size,
              live_disk_size,
              garbage_disk_size,
          })
      }
  }
  ```
]

这里可以看得出来，`BitCask`实现了`delete`，`flush`，`get`，`scan`，`set`，`status`这几个方法。大多数都是调用了`log`的方法。
- `delete`会将key/value对写入到log文件中，并且在keydir中删除这个key
- `flush`会将缓冲区的内容写出到存储介质中
- `get`会从keydir中获取value的位置以及长度，然后从log文件中读取value
- `scan`会返回一个`ScanIterator`，用于遍历keydir
- `set`会将key/value对写入到log文件中，并且在keydir中插入这个key
- `status`会返回存储引擎的状态



=== ToyDB中BitCask的取舍
在ToyDB中，BitCask的实现做了相当程度的简化：
+ ToyDB没有使用固定大小的日志文件，而是使用了任意大小的仅追加写的日志文件。这会增加压缩量，因为每次压缩的时候都会重写整个日志文件，并且也可能会超过文件系统的文件大小限制
+ 压缩的时候会阻塞所有的读以及写操作，这问题不大，因为ToyDB只会在重启的时候压缩，并且文件应该也比较小
+ 没有hint文件，因为ToyDB的value预估都比较小，hint文件的作用不大(其大小与合并的Log文件差不多大)
+ 每一条记录没有timestamps以及checksums
+ BitCask需要key的集合在内存中，而且启动的时候需要扫描log文件来构建索引
+ 与LSMTree不同，单个文件的BitCask需要在压缩的过程中重写整个数据集，这会导致显著的写放大问题
+ ToyDB没有使用任何压缩，比如可变长度的整数


== ToyDB中的内存存储引擎

TODO： 比较简单，可以直接看代码。

== MVCC事务
MVCC#footnote("Multi-Version Concurrency Control： https://zh.wikipedia.org/wiki/多版本并发控制")是广泛使用的并发控制机制，他为ACID事务提供快照隔离#footnote("https://jepsen.io/consistency/models/snapshot-isolation")，能实现读写并发。快照隔离级别是最高的隔离级别么? 并不是，最高的隔离级别是可串行化隔离级别，但是可串行化隔离级别会导致性能问题，所以快照隔离级别是一个折中的选择。

快照隔离级别会导致写倾斜(Write Skew)问题#footnote("https://justinjaffray.com/what-does-write-skew-look-like/")，但是这个问题在实际中并不常见。详细的讨论可以参考@write-skew。

=== MVCC在ToyDB中的实现

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

事务管理的`Key`枚举类的值会通过序列化成存储引擎中的`Key`来存储。这一点对于理解下面MVCC的实现非常重要。关于序列化的实现，会在 @encoding 详细说明#footnote("关于序列化也可以阅读一下： " + "https://research.cs.wisc.edu/mist/SoftwareSecurityCourse/Chapters/3_5-Serialization.pdf")，这里只需要知道实现了`serde`的`Deserialize`和`Serialize`两个`trait`就可以通过`encode()`将一个对象序列化成`vec<u8>`，通过`decode()`把`vec<u8>`反序列化成一个对象就可以了。

另外，通过`serde`的`with = "serde_bytes"`和`borrow`可以将`Cow`类型的数据序列化成`vec<u8>`，这个在`Key`枚举类中会用到。

下面来看一下`Key`枚举类的定义。

#code("toydb/src/storage/mvcc.rs", "Key 枚举类")[
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

#code("toydb/src/storage/mvcc.rs", "KeyPrefix 枚举类")[
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

#code("toydb/src/storage/mvcc.rs", "Key 与 KeyPrefix 的测试用例")[
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


#reference-block("Rust中的写时复制")[
  在上面`Key`以及`KeyPrefix`枚举类中多次出现了COW类型，这里简单介绍一下COW。

  COW（copy on wirte，写时复制）这是一个非常常见的概念。在Rust中，`Cow`是一个枚举类，有两个值，`Borrowed`和`Owned`，`Borrowed`表示借用，`Owned`表示拥有。

  当一个`Cow`是`Borrowed`的时候，它是一个引用，当一个`Cow`是`Owned`的时候，它是一个拥有者。

  通过`Cow`可以实现写时复制，也就是说，当一个`Cow`是`Borrowed`的时候，如果需要修改，就会复制一份，然后修改这份拷贝，这样就不会影响原来的数据。

  看一下这段代码能简单的理解一下COW。
  ```rust
  use std::borrow::Cow;
  fn process_data(input: &str, modify: bool) -> Cow<str> {
      if modify {
          let mut owned_string = input.to_string();
          owned_string.push_str("(modified)");
          Cow::Owned(owned_string)
      } else {
          Cow::Borrowed(input)
      }
  }

  /*
    结果为：
    Result 1: this is a test string, Address: 0x56a76d9d3213
    Result 2: this is a test string, Address: 0x56a76d9d3213
    Result 3: this is a test string(modified), Address: 0x56a76f1efb80
  */
  fn main() {
      let test_string = "this is a test string";
      let result1 = process_data(test_string, false);
      let result2 = process_data(test_string, false);
      let result3 = process_data(test_string, true);
      println!("Result 1: {}, Address: {:?}", result1, result1.as_ptr());
      println!("Result 2: {}, Address: {:?}", result2, result2.as_ptr());
      println!("Result 3: {}, Address: {:?}", result3, result3.as_ptr());
  }

  ```
]

看完了 `Key` 和 `KeyPrefix`，就来具体看一下MVCC的实现了。不过还有一个前置点是需要理解ToyDB中`MVCC`与`Transaction`的关系。

先看一下MVCC的代码。

#code("toydb/src/storage/mvcc.rs", "MVCC")[
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

在代码中可以看到，MVCC中更多的对Transaction以及存储引擎的一层封装。在一个事务想要开启的时候，先通过`MVCC`来开启一个（读写/只读）事务，之后关于事务的处理就不再属于`MVCC`来管理，转而到了稍后会讲到的`Trancation`中。


当事务开始的时候，从`Key::NextVersion`获取下一个可用的version并且递增它，然后通过`Key::TxnActive(version)`将自身记录为活动中的事务。它还会将当前活动的事务做一个快照，其中包含了事务开始的时候其他所有活动事务的version，并且将起另存为`Key::TxnActiveSnapshot(id)`。

key/value保存为`Key::Version(key, version)`的形式，其中`key`是用户提供的key，`version`是事务的版本。事务的key/value的可见性如下：
- 对于给定的key，从当前事务的版本开始对`Key::Version(key, version)`进行反向的扫描。
- 如果一个版本位于活动集(active set)中的时候，跳过这个版本。
- 返回第一个匹配记录（如果有的话），这个记录可能是`Some(value)`或者`None`。

写入key/value的时候，事务首先要扫描其不可见的`Key::Version(key, version)`来检查是否存在任何冲突。如果有找到一个，那么需要返回序列化错误，调用者必须重试这个事务。如果没有找到，事务就会写入新记录，并且以`Key::TxnWrite(version, key)`的形式来跟踪更改，以防必须回滚的情况。

当事务提交的时候，就只需要删除其`Txn::Active(id)`记录，使其更改对其他后续的事务可见就可以了。如果事务回滚，就遍历所有的`Key::TxnWrite(id, key)`记录，并删除写入的key/value值，最后删除`Txn::Active(id)`记录就可以了。

这个方案可以保证ACID事务的快照隔离： 提交是原子的，每一个事务在开始的时候，看到的都是key/value存储的一致性快照，并且任何写入冲突都会导致序列化冲突，必须重试。

为了实现时间穿梭查询，只读事务只需加载过去事务的`Key::TxnActiveShapshot`记录就可以了，可见性规则和普通事务是一样的。

=== MVCC在ToyDB中的取舍
+ 旧的MVCC版本永远不会被删除，会导致存储空间的浪费。但是这简化了实现，也允许完整的数据历史记录。
+ 事务id会在64位后溢出，没有做处理。

== 总结