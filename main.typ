#import "typst-book-template/book.typ": *

#set text(lang: "zh")
#show: book.with(info: (
  name: "Quhaha",
  title: "从零开始的分布式数据库生活 \n (From Zero to Distributed Database)",
))

#include "src/chapter1.typ"
#include "src/chapter2.typ"
#include "src/chapter3.typ"
#include "src/chapter4.typ"
#include "src/chapter5.typ"
#include "src/chapter6.typ"