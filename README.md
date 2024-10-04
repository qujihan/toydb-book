<div align="center">
<strong>
<samp>
</samp>
</strong>
</div>

# WIP. 从零开始的分布式数据库生活
现在用的typst 0.12, Github Action还没有支持, 暂时过不了CI. 
[![Generate PDF](https://github.com/qujihan/toydb-book/actions/workflows/build.yml/badge.svg)](https://github.com/qujihan/toydb-book/actions/workflows/build.yml)
[![下载最新版本](https://img.shields.io/badge/%E7%82%B9%E8%BF%99%E9%87%8C-%E4%B8%8B%E8%BD%BDrelease%E7%89%88%E6%9C%AC-red.svg "下载最新版本")](https://nightly.link/qujihan/toydb-book/workflows/build/main/from_zero_to_distributed_database.pdf.zip)

# 编译本书

所需组件
- python(tqdm, requests)
- [typst](https://typst.app/)
- [typstyle]()

```shell
git clone https://github.com/qujihan/toydb-book.git

# 下载依赖
cd toydb-book && git submodule update --init --recursive

pip install requests # 下载字体使用
pip install tqdm # 为了下载界面好看一点

# 下载所需字体
# 与 python3 ./typst-book-template/fonts/download.py --proxy 相同
make font 

# 编译
# 与 python3 ./typst-book-template/op.py c 相同
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


# 一些推广
- [typst](https://typst.app/): 全新的排版工具
- [typst-book-template](https://github.com/qujihan/typst-book-template): typst生成书籍的模板, 本书使用的模板(为了本书专门写的, 后来改造成了一个模板)