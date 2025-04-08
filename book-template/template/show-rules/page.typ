#import "../consts.typ": *

#let page-header-content(info: (:)) = (
  context {
    let curr-font = (info.at(all-keys.latin-font), (name: info.at(all-keys.cjk-font), covers: "latin-in-cjk"))

    set align(center)

    let curr-page = here().page()

    let heading-1-anchors = query(selector(heading.where(level: 1))).map(it => it.location().page())

    let heading-2-anchors = query(selector(heading.where(level: 2))).map(it => it.location().page())

    let title1-infos = query(selector(heading.where(level: 1)).before(here()))
    let title2-infos = query(selector(heading.where(level: 2)).before(here()))

    let title1-body = ""
    let title2-body = ""
    if title1-infos.len() != 0 {
      title1-body = title1-infos.last().body
    }
    if title2-infos.len() != 0 {
      title2-body = title2-infos.last().body
    }

    if curr-page not in heading-1-anchors and curr-page not in heading-2-anchors {
      grid(
        columns: (1fr, 1fr),
        align: (left, right),
        text(size: 1em, fill: info.at(all-keys.content-color), baseline: 0.5em, font: curr-font, strong(title1-body)),
        text(size: 1em, fill: info.at(all-keys.content-color), baseline: 0.5em, font: curr-font, strong(title2-body)),
      )
      line(length: 100%, stroke: 0.7pt + info.at(all-keys.line-color))
    }

    if curr-page not in heading-1-anchors and curr-page in heading-2-anchors {
      grid(
        columns: (1fr),
        align: (center),
        text(size: 1em, fill: info.at(all-keys.content-color), baseline: 0.5em, font: curr-font, strong(title1-body)),
      )
      line(length: 100%, stroke: 0.7pt + info.at(all-keys.line-color))
    }
  }
)

#let page-footer-content(info: (:)) = (context {
  let curr-font = (info.at(all-keys.latin-font), (name: info.at(all-keys.cjk-font), covers: "latin-in-cjk"))
  set align(center)
  let curr-page = here().page()
  let heading-1-anchors = query(selector(heading.where(level: 1))).map(it => it.location().page())
  grid(columns: (7fr, 1fr, 7fr), line(length: 100%, stroke: 0.7pt + info.at(all-keys.line-color)), text(
    font: curr-font,
    fill: info.at(all-keys.content-color),
    0.8em,
    baseline: -3pt,
    strong(counter(page).display("1")),
  ), line(length: 100%, stroke: 0.7pt + info.at(all-keys.line-color)))
})

#let set-page-style(info, body) = {
  set page(paper: "a4", margin: auto, header: page-header-content(info: info), footer: page-footer-content(info: info))
  show page: it => {
    counter(footnote).update(0)
    it
  }
  body
}