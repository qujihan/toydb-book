#import "../consts.typ": *

#let set-doc-text-par-style(info, body) = {
  set document(title: info.at(all-keys.title), author: info.at(all-keys.author))

  set text(
    region: "cn",
    lang: "zh",
    font: (info.at(all-keys.latin-font), (name: info.at(all-keys.cjk-font), covers: "latin-in-cjk")),
  )

  set par(
    first-line-indent: (amount: 2em, all: true),
    justify: true,
    leading: 1em,
    linebreaks: "optimized",
    spacing: 1.3em,
  )

  body
}