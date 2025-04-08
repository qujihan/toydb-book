= 前言

```zsh
# 除了测试文件, 共有 41 个 golang 文件
find . -name "*.go" ! -name "*_test.go" | wc -l
# 接近 6000 行代码
find . -name "*.go" ! -name "*_test.go" | xargs cloc
# 但是真正需要看的, 只有这 11 个文件
files=(
    db.go
    page.go
    node.go
    unsafe.go
    freelist.go
    freelist_hmap.go
    bucket.go
    cursor.go
    tx.go
    tx_check.go
    errors.go
)
# 这就只有 3300 了, 少了接近一半
cloc ${files}
```

- db.go
    - 数据库对外提供的服务
- page.go node.go
    - page: 数据在磁盘中的形式
    - node: 数据在内存中的形式
- freelist.go freelist_hmap.go
    - 内存如何管理的
- bucket.go cursor.go
    - bucket: 数据如何组织的
    - cursor: 数据如何遍历的
- tx.go tx_check.go
    - 事务的实现
- unsafe.go
    - 封装了 unsafe 的操作
    - 主要用于 node ⇄ page
- errors.go
    - 定义一系列错误
