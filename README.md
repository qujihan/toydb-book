<div align="center">
<strong>
<samp>
</samp>
</strong>
</div>

# WIP. 从零开始的分布式数据库生活

[![Generate PDF](https://github.com/qujihan/toydb-book/actions/workflows/build.yml/badge.svg)](https://github.com/qujihan/toydb-book/actions/workflows/build.yml)
[![下载最新版本](https://img.shields.io/badge/%E7%82%B9%E8%BF%99%E9%87%8C-%E4%B8%8B%E8%BD%BDrelease%E7%89%88%E6%9C%AC-red.svg "下载最新版本")](https://nightly.link/qujihan/toydb-book/workflows/build/main/from_zero_to_distributed_database.pdf.zip)

# 编译本书

所需组件
- Python
- [Typst](https://typst.app/)

```shell
git clone https://github.com/qujihan/toydb-book.git
cd toydb-book
git submodule update --init --recursive
python fonts/download.py
make c
```

## TODO
正在把理解理成书中....
- 存储引擎
    - [√] Bitcask存储引擎
    - [√] MVCC
- 共识算法 Raft
    - [☓] Message
    - [☓] Node
    - [☓] Log
- SQL引擎
    - [√] Type
    - [☓] Engine
    - [☓] Parse
    - [☓] Planner
    - [☓] Execution
- [☓] 编码