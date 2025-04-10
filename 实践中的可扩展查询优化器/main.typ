#import "lib.typ": *

#set text(lang: "zh")
#show: book.with(info: (
  title: "实践中的可扩展查询优化器",
  author: "作者: Microsoft 译者: 渠继涵",
  latin-font: "Lora",
  cjk-font: "Noto Serif CJK SC",
  code-font: "Maple Mono NF",
))

#show: sql-code-show-stype.with()
#show: algorithm-code-show-stype.with()

#include "src/1介绍.typ"
#include "src/2可扩展的查询优化器.typ"
#include "src/3业界其他可扩展的查询优化器.typ"
#include "src/4执行计划的关键转化.typ"
#include "src/5代价估计.typ"
#include "src/6执行计划管理.typ"
#include "src/7开放性问题.typ"
#include "src/8附录.typ"
#include "src/9致谢附录参考文献.typ"
#set text(lang: "en")
#bibliography("ref.bib", title: "参考文献")
