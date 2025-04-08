== SSTable

SSTable是`Sorted String Table`的缩写，是用于持久化有序键值对的数据结构。

这一部分涉及的代码为：
- `table/*`

在LevelDB中，SST的文件包含以下几块：
+ data blocks：存放了Key-Value数据
+ meta blocks：在LevelDB中是存放了BloomFilter的数据
+ meta index block：
+ index block：
+ footer：
  + `metaindex_handle`：指向meta index block的`BlockHandle`
  + `index_handle`：指向index block的`BlockHandle`
  + `padding`：
  + `magic_number`：魔数，用于校验文件是否是SST文件


=== Block

`Block`的作用：
+ 保存`BlockContents`转换后的数据，存储在`Cache`中。
+ 由于SST中存储的Block存在多个item，因此需要一个迭代器来遍历。
