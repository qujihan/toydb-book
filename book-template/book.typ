#import "template/mod.typ": *

#let book(info: (:), body) = {
  let info = info-check(info: info)

  show: set-doc-text-par-style.with(info)
  show: set-page-style.with(info)
  show: set-emph-style.with(info)
  show: set-enum-style.with()
  show: set-footnote-style.with(info)
  show: set-raw-style.with(info)
  show: figure-env-set.with(info)

  if info.at(all-keys.display-cover) {
    display-cover(info.at(all-keys.title), info.at(all-keys.author))
  }

  if info.at(all-keys.display-outline) {
    display-outline(info.at(all-keys.outline-depth))
  }

  counter(page).update(1)
  show: set-heading-style.with()

  body
}
