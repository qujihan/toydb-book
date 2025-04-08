#import "../consts.typ": *

#let set-footnote-style(info, body) = {
  let curr-font = (info.at(all-keys.latin-font), (name: info.at(all-keys.cjk-font), covers: "latin-in-cjk"))
  show footnote.entry: set text(font: curr-font, size: 0.8em, fill: info.content-color)
  set footnote.entry(clearance: 0.8em, gap: 0.8em, indent: 0em)
  body
}