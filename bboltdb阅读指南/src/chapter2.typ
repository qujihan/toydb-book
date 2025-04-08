= BoltDB的数据组织方式
每一个 Bucket 对应一棵 B+ 树

先看一下 Bucket 的定义
```go
type bucket struct {
	root     pgid   // page id of the bucket's root-level page
	sequence uint64 // monotonically incrementing, used by NextSequence()
}

type Bucket struct {
	*bucket
    // 当前 Bucket 关联的事务
	tx       *Tx                // the associated transaction
    // 子 Bucket
	buckets  map[string]*Bucket // subbucket cache
    // 关联的 page
	page     *page              // inline page reference
    // Bucket 管理的树的根节点
	rootNode *node              // materialized node for the root page.
    // 缓存
	nodes    map[pgid]*node     // node cache

	// Sets the threshold for filling nodes when they split. By default,
	// the bucket will fill to 50% but it can be useful to increase this
	// amount if you know that your write workloads are mostly append-only.
	//
	// This is non-persisted across transactions so it must be set in every Tx.
    // 填充率
    // 与B+树的分裂相关
	FillPercent float64
}
```

== Bucket 中重要的工具 Cursor 游标

bolt 中没有使用传统的 B+ 树中将叶子节点使用链表串起来的方式, 而是使用的 cursor游标, 通过路径回溯的方式, 来支持范围查询. 

所以 cursor 对于 bucket 中 curd 还是听重要的. 
```go
type elemRef struct {
    // 当前位置对应的 page
	page  *page
    // 当前位置对应的 node
    // 可能是没有被反序列化的
    // 但是没关系, 使用page可以序列化
	node  *node
    // 在第几个 kv 对
	index int
}
type Cursor struct {
	bucket *Bucket
	stack  []elemRef
}
```
