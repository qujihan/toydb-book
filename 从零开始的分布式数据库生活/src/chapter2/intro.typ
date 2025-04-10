#import "../../lib.typ": *

#code-figure(
  // "tree src/storage",
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

== 存储引擎介绍

存储引擎是干什么的。现在假设对面的同学是一个对数据库一无所知的同学，下面从两个方面来介绍一个存储引擎。

站在存储引擎的调用者来看，存储引擎就是一个随意使用的HashMap。当我给定一个key，存储引擎就会返回一个value。或者我将key的值设置为value。在稍后的`storage::Engine`我们将会看到。

其实上面有一个默认的假设是，存储引擎是一个线程安全的。但是在实际的系统中并不一定是线程安全的。那么如何解决呢？解决方式其实很简单，就是在存储引擎的外面加一个锁。这样就可以保证线程安全了。

那加锁是不是效率有点太低了呢？其实这个也与锁的粒度有关。如果锁的粒度太大，那么就会导致性能下降。如果锁的粒度太小，那么就会导致锁的争用。所以在实际的系统中，需要根据实际情况来选择锁的粒度。

在本书的存储引擎中，会提到一个MVCC的事务。MVCC是一种多版本并发控制，它可以在不加锁的情况下实现事务的隔离。

这里又出现了一个陌生的名词，事务。事务是数据库中的一个重要概念，它是一组操作的集合，这组操作要么全部成功，要么全部失败。在数据库中，事务有四个特性，ACID。分别是原子性(Atomicity)，一致性(Consistency)，隔离性(Isolation)，持久性(Durability)。这四个特性是数据库中事务的基本要求。

当然存储引擎与编程语言中的HashMap还有一个不同是，它可以是持久化的，也就是说，当程序退出的时候，数据还是会保存在磁盘上。这样就可以保证数据不会丢失。

ToyDB是一个分布式数据库，它实现的存储引擎不仅被SQL引擎使用，还被Raft引擎使用。在Raft引擎中，存储引擎是用来存储Raft的日志的。在SQL引擎中，存储引擎是用来存储数据的。

下面我们看一下这里存储引擎所需要实现的trait。