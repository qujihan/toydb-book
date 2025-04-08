#import "../../lib.typ": *

== BitCask 存储引擎
ToyDB使用的可持久化的存储引擎是BitCask(参考@bitcask)的*变种*。简单来说，就是在写入的时候，先写入到只能追加写的log文件中，然后在内存中维护一个索引，索引内容为
(key -> 文件位置以及长度)。

当垃圾量(包含替换以及删除的key)大于一定阈值的时候，将在内存中的key写入到新的log文件中，然后替换老的log文件。替换的过程被称为压缩，会导致写放大问题，但是可以通过控制阈值来减小影响。

通过上面的描述，可以分析出几个语义：
- BitCask要求所有的Key必须能存放在内存中。
- BitCask在启动的时候需要扫描Log文件来构建索引。
- 删除文件的时候并不是真正的删除。
  - 实际上是写入一个墓碑值(tombstone value)，读取到墓碑值就认为是删除了。

下面先看一下ToyDB的宏观架构，再自底向上的看一下实现过程。
#code-figure(
  //   "toydb/src/storage/bitcask.rs",
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

其中`keydir`是一个BTree，key是一个Vec<u8>，value是一个元组(u64,
u32)，其中u64是value在Log文件中的位置，u32是value的长度。这个结构是有序的，这样就可以进行范围查询。

再来看`log`，它包含了一个文件路径`path`以及一个文件句柄`file`。这个文件是只追加写的，这样就可以保证写入的顺序是正确的。

下面先看`log`实现部分，再来回看`BitCask`的部分。

=== Log的实现
每一个log entry包含四个部分：
- Key 的长度，大端u32
- Value 的长度，大端i32，-1 表示墓碑值
- Key 的字节序列(最大 2GB)
- Value 的字节序列(最大 2GB)

在Log中，`new`比较简单，是打开一个log文件，当不存在的时候就创建这个文件。并且在使用过程中一直使用的排它锁，这样就可以保证只有一个线程在写入。

#code-figure(
  //   "toydb/src/storage/bitcask.rs",
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

#code-figure(
  // "toydb/src/storage/bitcask.rs",
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

#code-figure(
  // "toydb/src/storage/bitcask.rs",
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

#code-figure(
  // "toydb/src/storage/bitcask.rs",
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
=== BitCask的实现

在知道了`log`是如何实现的以后，就可以更好的理解BitCask的实现了。回忆一下，@bitcask_code 中，`BitCask`中包含了一个`log`以及一个`keydir`。`log`用来写入KV对，`keydir`用来维护内存中的索引。

下面先看一下`BitCask`中的一些周边函数，然后再看一下如何实现`Engine`这个trait。

先来看看`BitCask`的构造函数以及析构函数，`new`和`new_compact`。这个两个函数的区别就是`new_compact`会在打开的时候自动压缩。关于析构函数，会在Drop的时候尝试flush文件。

#code-figure(
  // "toydb/src/storage/bitcask.rs",
  "impl Bitcask",
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

#code-figure(
  // "toydb/src/storage/bitcask.rs",
  "compact / write_log",
)[
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

#code-figure(
  // "",
  "",
)[
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
