= BoltDB在磁盘中的形式

= bolt 在磁盘中是什么形式
下面描述一下 bolt 的文件在磁盘中是什么形式存储的, 也就是真正在磁盘中的时候是什么样子的

page 的类型
- meta page
- freelist page
- branch page
- leaf page


== Head
定义于 page.go 中, 每一个 page 都共有的结构

这里只描述一次, 后面的各种类型的 page 就不说明这一部分了
```go
┌────┬───────┬───────┬──────────┐
│ id │ flags │ count │ overflow │ (8+2+2+4)bytes
└────┴───────┴───────┴──────────┘
type pgid uint64
type page struct {
	id       pgid   // 每个页的唯一id
	flags    uint16 // 类型
	count    uint16 // 页中元素的数量
	overflow uint32 // 数据是否有溢出(主要是freelist page中有用)
}
```


== meta page 的内容
元信息页, 定义于 db.go 中, 主要的作用是管理整个数据库必要信息
```go
type meta struct {
	magic    uint32 // 魔数
	version  uint32 // 版本号(固定为2)
	pageSize uint32 // 页大小(4KB)
	flags    uint32
	root     bucket
	freelist pgid   // 空闲列表页的 page id
	pgid     pgid
	txid     txid   // 数据库事务操作序号
	checksum uint64 // data数据的hash摘要, 用于判断data是否损坏
}
```

== freelist page
定义于 freelist.go 中


磁盘中的格式
```go
┌────┬───────┬─────────────────┬──────────┐
│ id │ flags │ count(< 0xffff) │ overflow │ (8+2+2+4)bytes
├────┴─┬─────┴┬──────┬──────┬──┴───┬──────┤
│ pgid │ pgid │ pgid │ .... │ pgid │ pgid │ (8*n)bytes
└──────┴──────┴──────┴──────┴──────┴──────┘

┌────┬───────┬──────────────────┬──────────┐
│ id │ flags │ count(>= 0xffff) │ overflow │ (8+2+2+4)bytes
├────┴──┬────┴─┬──────┬──────┬──┴───┬──────┤
│ COUNT │ pgid │ pgid │ .... │ pgid │ pgid │ (8*n)bytes
└───────┴──────┴──────┴──────┴──────┴──────┘
```

== branch page 的内容
定义在 page.go 中
```go
type branchPageElement struct {
	pos   uint32
	ksize uint32
	pgid  pgid
}

a-->┌────┬───────┬───────┬──────────┐
    │ id │ flags │ count │ overflow │ (8+2+2+4)bytes
b-->├────┴─┬─────┴──┬────┴──┬───────┘
    │ pos1 │ ksize1 │ pgid1 │ (4+4+8)bytes
c-->├──────┼────────┼───────┤
    │ pos2 │ ksize2 │ pgid2 │ (4+4+8)bytes
    ├──────┴────────┴───────┤
    │ ..................... │ 
    ├──────┬────────┬───────┤
    │ posn │ ksizen │ pgidn │ (4+4+8)bytes
d-->├──────┼────────┴───────┘
    │ key1 │ 
e-->├──────┤
    │ key2 │
    ├──────┤
    │ .... │ 
    ├──────┤
    │ keyn │
    └──────┘
```
pos 实际上就是 key 相对于 head 结尾的偏移量

如图:
```
a = 0
b = 16*8
c = 16*8 + 16*8
pos1 = d-b
pos2 = e-c
```

== leaf page 的内容
```go
// page.go
type leafPageElement struct {
    // 标识当前的节点是否是 bucket 类型
    // page.go 定义了 bucketLeafFlag = 0x01
    // 0 不是 bucket 类型
    // 1 是 bucket 类型
	flags uint32
	pos   uint32
	ksize uint32
	vsize uint32
}

a-->┌────┬───────┬───────┬──────────┐
    │ id │ flags │ count │ overflow │ (8+2+2+4)bytes
b-->├────┴──┬────┴─┬─────┴──┬───────┴┐
    │ flags │ pos1 │ ksize1 │ vsize1 │ (4+4+4+4)bytes
c-->├───────┼──────┼────────┼────────┤
    │ flags │ pos2 │ ksize2 │ vsize2 │ (4+4+4+4)bytes
    ├───────┴──────┴────────┴────────┤
    │ .............................. │ 
    ├───────┬──────┬────────┬────────┤
    │ flags │ posn │ ksizen │ vsizen │ (4+4+4+4)bytes
d-->├──────┬┴──────┴┬───────┴────────┘
    │ key1 │ value1 │ 
e-->├──────┼────────┤
    │ key2 │ value2 │ 
    ├──────┴────────┤
    │ ............. │ 
    ├──────┬────────┤
    │ keyn │ valuen │ 
    └──────┴────────┘
```

pos 实际上就是 kv 相对于 head 结尾的偏移量
如图:
```
a = 0
b = 16*8
c = 16*8 + 16*8
pos1 = d-b
pos2 = e-c
```