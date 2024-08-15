#import "typst-book-template/book.typ": *

#set text(lang: "zh")
#show: book.with(info:(
  title: "从零开始的分布式数据库生活 \n (From Zero to Distributed Database)",
  name: "Quhaha",
  latin-font: ("Lora"),
  cjk-font: ("Source Han Serif SC",),
  code-font: ("CaskaydiaCove NF",),
))

#set heading(supplement: "")
#show ref: it => {
  if it.element.func() == heading {
    link(it.target, "第" + it + "章" + it.element.body)
  } else {
    link(it.target, it)
  }
}

#include "src/chapter1.typ"
#include "src/chapter2.typ"
#include "src/chapter3.typ"
#include "src/chapter4.typ"
#include "src/chapter5.typ"
#include "src/chapter6.typ"
#include "src/chapter7.typ"