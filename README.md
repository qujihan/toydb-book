# 从零开始的数据库生活(toyDB走读笔记)

> [toyDB](https://github.com/erikgrinaker/toydb) 仓库

# 编译本书
- python(以及tqdm模块)
- typst
- typstyle(格式化typ代码所需)

```shell
git clone https://github.com/qujihan/toydb-book.git

# 下载依赖
cd toydb-book && git submodule update --init --recursive

# 推荐安装 tqdm(只是为了下载界面好看一点)
# pip install tqdm

# 下载所需字体
python typst-book-template/fonts/download.py

# 编译
python typst-book-template/op.py c
```