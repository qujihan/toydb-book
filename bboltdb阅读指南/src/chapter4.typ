= BoltDB在内存中的形式

page 是物理存储的基本单位, 那么 node 就是在逻辑存储的基本单位. 也是在内存中存储的单位

位于 node.go 下的 type node struct{}

node 只是描述了 branch/leaf page 在内存中的格式

而 meta/freelist page 在内存中是在 DB 结构体中, 他们也有专门的结构体 type meta struct{} 以及 type freelist struct{}. 分别位于 db.go 与 freelist.go 中

```go
type nodes []*node
type inode struct {
    // branch page OR leaf page
	flags uint32
    // 如果类型是 branch page 时
    // 表示的是 子节点的 page id
	pgid  pgid
	key   []byte
    // 如果类型是 leaf page 时
    // 表示的是 kv 对中的值(value)
	value []byte
}
type inodes []inode

type node struct {
    // 该 node 节点位于哪个 bucket
	bucket     *Bucket
    // 是否是叶子节点
    // 对应到 page header 中的 flags 字段
	isLeaf     bool
    // 是否平衡
	unbalanced bool
    // 是否需要分裂
	spilled    bool
    // 节点最小的 key
	key        []byte
    // 节点对应的 page id
	pgid       pgid
    // 当前节点的父节点
	parent     *node
    // 当前节点的孩子节点
    // 在 spill rebalance 过程中使用
	children   nodes
    // 节点中存储的数据
    // 广义的 kv 数据(v 可能是子节点)
    // page header 中的 count 可以通过 len(inodes) 获得
    // branch/leaf 的数据都在 inodes 中可以体现到
	inodes     inodes
}
```

== node 以及 page 的转换(branch/leaf page)

在这里可以清楚的看到branch/leaf的磁盘内存的转换过程

```go
// node.go

// 读入
func (n *node) read(p *page)
// 落盘
func (n *node) write(p *page)
```

== node 以及 page 的转换(meta page)
```go
// 内存中的 meta 结构
type meta struct {
	magic    uint32
	version  uint32
	pageSize uint32
	flags    uint32
    // 对应一个 root bucret
	root     bucket
	freelist pgid
	pgid     pgid
	txid     txid
	checksum uint64
}

// 读入
// db启动的时候就会先读入
func (db *DB) mmap(minsz int) (err error) {
    // ....
    db.meta0 = db.page(0).meta()
    db.meta1 = db.page(1).meta()
    // ...
}
func (p *page) meta() *meta {
	return (*meta)(unsafeAdd(unsafe.Pointer(p), unsafe.Sizeof(*p)))
}

// 落盘
// 每一次事务 commit 的时候都会调用
// Note: read only不会改变 meta, 只有 read-write 会改变 meta 信息
// (tx *Tx)Commit -> (tx *Tx)writeMeta -> (m *meta)write
// db.go
func (m *meta) write(p *page) 
```




== node 以及 page 的转换(freelist page)
```go
// 读入 freelist.go
func (f *freelist) read(p *page) 
// 落盘 freelist.go
func (f *freelist) write(p *page) error 
```
