#import "../typst-book-template/book.typ": *
= 存储引擎

ToyDB使用一个可替换的key/value存储引擎, 通过storage_sql和storage_raft选项分别配置SQL和Raft存储引擎. 关于更高层的SQL存储引擎将在SQL部分单独讨论.

== 二进制编码

=== Key/Value存储

在ToyDB中, 存储引擎可以将任意的key/value作为字节切片(byte slice)存储起来, 另外还需要实现`storage::Engine`这个trait.

#let block = "一个key/value的存储引擎可以存储任意的byte strings, 其中key是以字母序排列的.
有序的key可以高效的进行范围查询, 这个在一些场景还是非常有用的, 比如在执行一个扫描表的SQL的时候(所有的行都是以相同的key前缀).
所有的key都应该使用 `KeyCode` 进行编码.
另外在在写入后, 只有调用 flush() 之后才能保证数据持久化.
"
#referenceBlock(block)

#code(
  "toydb/src/storage/engine.rs",
  "strong::Engine",
  ```rust
pub trait Engine: Send {
    // scan()返回的迭代器
    type ScanIterator<'a>: ScanIterator + 'a
    where
        Self: Sized + 'a; // 为了对象安全, 忽略// omit in trait objects, for object safety

    /// Deletes a key, or does nothing if it does not exist.
    fn delete(&mut self, key: &[u8]) -> Result<()>;

    /// Flushes any buffered data to the underlying storage medium.
    fn flush(&mut self) -> Result<()>;

    /// Gets a value for a key, if it exists.
    fn get(&mut self, key: &[u8]) -> Result<Option<Vec<u8>>>;

    /// Iterates over an ordered range of key/value pairs.
    fn scan(&mut self, range: impl std::ops::RangeBounds<Vec<u8>>) -> Self::ScanIterator<'_>
    where
        Self: Sized; // omit in trait objects, for object safety

    /// Like scan, but can be used from trait objects. The iterator will use
    /// dynamic dispatch, which has a minor performance penalty.
    fn scan_dyn(
        &mut self,
        range: (std::ops::Bound<Vec<u8>>, std::ops::Bound<Vec<u8>>),
    ) -> Box<dyn ScanIterator + '_>;

    /// Iterates over all key/value pairs starting with prefix.
    fn scan_prefix(&mut self, prefix: &[u8]) -> Self::ScanIterator<'_>
    where
        Self: Sized, // omit in trait objects, for object safety
    {
        self.scan(keycode::prefix_range(prefix))
    }

    /// Sets a value for a key, replacing the existing value if any.
    fn set(&mut self, key: &[u8], value: Vec<u8>) -> Result<()>;

    /// Returns engine status.
    fn status(&mut self) -> Result<Status>;
}




/// A key/value storage engine, where both keys and values are arbitrary byte
/// strings between 0 B and 2 GB, stored in lexicographical key order. Writes
/// are only guaranteed durable after calling flush().
/// 一个 key/value 的存储引擎. 其中 keys 以及 values 可以存大小在 0B~2GB 的 bytes.
/// 其中存放的顺序是字母序. 只有在调用 flush() 以后才可以保证写入的持久化.
///
/// Only supports single-threaded use since all methods (including reads) take a
/// mutable reference -- serialized access can't be avoided anyway, since both
/// Raft execution and file access is serial.
/// 这里仅支持单线程, 即使是 reads. 因为他们都需要一个可变引用. 因为Raft的执行和文件访问都是
/// 串行的, 无论如何都无法避免序列化.
pub trait Engine: std::fmt::Display + Send + Sync {
    /// The iterator returned by scan(). Traits can't return "impl Trait", and
    /// we don't want to use trait objects, so the type must be specified.
    /// scan() 返回的迭代器. Traits 不能返回一个 "impl Trait", 并且我们也不想使用 trait 对象
    /// 所以我们在这里必须指定一个类型.
    type ScanIterator<'a>: DoubleEndedIterator<Item = Result<(Vec<u8>, Vec<u8>)>> + 'a
    where
        Self: 'a;

    /// Deletes a key, or does nothing if it does not exist.
    /// 删除一个 key. 当这个 key不存在的时候就什么都不做.
    fn delete(&mut self, key: &[u8]) -> Result<()>;

    /// Flushes any buffered data to the underlying storage medium.
    // 将缓冲区的数据写入到底层的存储介质中.
    fn flush(&mut self) -> Result<()>;

    /// Gets a value for a key, if it exists.
    /// 得到 key 所对应的 value, 如果存在的话.
    fn get(&mut self, key: &[u8]) -> Result<Option<Vec<u8>>>;

    /// Iterates over an ordered range of key/value pairs.
    /// 遍历指定范围内的 key/value 对.
    fn scan<R: std::ops::RangeBounds<Vec<u8>>>(&mut self, range: R) -> Self::ScanIterator<'_>;

    /// Sets a value for a key, replacing the existing value if any.
    // 将 key 设置能 value, 如果存在就替换掉.
    fn set(&mut self, key: &[u8], value: Vec<u8>) -> Result<()>;
}
  ```
)

其中的`get`, `set`以及`delete`只是简单的读取以及写入key/value对, 并且通过`flush`可以确保将缓冲区的内容写出到存储介质中(比如通过`fsync`这个系统调用). `scan`按照顺序迭代指定的key/value对范围. 这个对一些高级功能(比如:SQL表扫描)至关重要. 并且暗含了以下一些语义: 
- 为了提高性能, 存储的数据应该是有序的. 
- key应该保留字节编码, 这样才能实现范围扫描.

对于存储引擎而已, 并不关心`key`是什么, 但是为了方便上层的调用, 提供了一个称为`KeyCode`的order-preserving#footnote("TODO")编码. 

// TODO 没看懂这里啥玩意这是


ToyDB使用的存储引擎是BitCask#footnote("https://riak.com/assets/bitcask-intro.pdf")的变种, 在写入的时候, 先写入到log文件中, 索引会在内存中维护key与文件位置的关系. 当垃圾量(包含替换以及删除的key)大于20%的时候, 将在内存中的key写入到新的log文件中, 替换掉老的log文件.

=== key/value中实现的取舍
+ BitCask需要key的集合在内存中, 而且启动的时候需要扫描log文件来构建索引.
+ 与LSMTree不同, 单个文件的BitCask需要在压缩的过程中重写整个数据集, 这会导致显著的写放大问题.
+ ToyDB没有使用任何压缩, 比如可变长度的整数.

== MVCC事务
MVCC (Multi-Version Concurrency Control)#footnote("TODO") (多版本并发控制)是一种比较简单的并发控制机制, 他为ACID事务提供快照隔离#footnote("TODO"), 从而无须锁就能实现写与读的冲突. 它还可以对所有数据进行版本控制, 允许查询历史的数据. 

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

=== MVCC中的取舍
+ 只是实现了快照隔离级别, 并没有实现可序列化隔离级别. 会导致写倾斜(write skew)问题#footnote("https://justinjaffray.com/what-does-write-skew-look-like/").
+ 旧的MVCC版本永远不会被删除, 会导致存储空间的浪费.但是这简化了实现, 也允许完整的数据历史记录.
+ 事务id会在64位后溢出, 没有做处理