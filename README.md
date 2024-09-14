# 从零开始的分布式数据库生活(ToyDB走读笔记)

> [ToyDB](https://github.com/erikgrinaker/toydb) 仓库

# 编译本书

所需组件
- python(以及tqdm模块)
- typst
- typstyle(格式化typ代码所需)

```shell
git clone https://github.com/qujihan/toydb-book.git

# 下载依赖
cd toydb-book && git submodule update --init --recursive

pip install requests # 下载字体使用
pip install tqdm # 为了下载界面好看一点

# 下载所需字体
python typst-book-template/fonts/download.py

# 编译
make c # 实际调用的是 typst-book-template/op.py c
```