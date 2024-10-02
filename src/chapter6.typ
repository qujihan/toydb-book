#import "../typst-book-template/book.typ": *
#let path-prefix = figure-root-path + "src/pics/"

= 附录
#show heading.where(level: 2):it=>{
  pagebreak(weak: true)
  it
}

== 一些环境的准备

== BitCask的论文解读 <bitcask>
=== 参考
+ https://riak.com/assets/bitcask-intro.pdf
+ https://arpitbhayani.me/blogs/bitcask/

== 隔离级别
=== 写倾斜(Write Skew)问题 <write-skew>
=== 参考
+ https://justinjaffray.com/what-does-write-skew-look-like/