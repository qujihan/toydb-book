# WIP
# 从零开始的分布式数据库生活(From Zero to Distributed Database)

## TODO
正在把理解理成书中....
- 存储引擎
    - [ ] Bitcask存储引擎
    - [ ] MVCC
- 分布式算法
    - [ ] Raft
- SQL
    - [ ] SQL解析
    - [ ] SQL优化
    - [ ] SQL执行

# 编译本书

所需组件
- python(tqdm, requests)
- typst
- typstyle(格式化typ代码所需)

```shell
git clone https://github.com/qujihan/toydb-book.git

# 下载依赖
cd toydb-book && git submodule update --init --recursive

pip install requests # 下载字体使用
pip install tqdm # 为了下载界面好看一点

# 下载所需字体
make font # python3 ./typst-book-template/fonts/download.py --proxy

# 编译
make c # python3 ./typst-book-template/op.py c
```