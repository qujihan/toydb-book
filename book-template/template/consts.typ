#let all-keys = (
  // basic info
  "title": "title",
  "author": "author",
  // book info
  "display-cover": "display-cover",
  "display-outline": "display-outline",
  "outline-depth": "outline-depth",
  "content-font-size": "content-font-size",
  // font
  "cjk-font": "cjk-font",
  "latin-font": "latin-font",
  "code-font": "code-font",
  // color
  "content-color": "content-color",
  "line-color": "line-color",
  "emph-color": "emph-color",
  "inline-code-color": "inline-code-color",
)

#let all-key-and-default-value = (
  // basic info
  all-keys.title: "Unnamed book",
  all-keys.author: "Unnamed author",
  // book info
  all-keys.display-cover: true,
  all-keys.display-outline: true,
  all-keys.outline-depth: 3,
  all-keys.content-font-size: 10pt,
  // font
  all-keys.cjk-font: "",
  all-keys.latin-font: "",
  all-keys.code-font: "",
  // color
  all-keys.content-color: rgb("#000000"),
  all-keys.line-color: rgb("#000000"),
  all-keys.emph-color: rgb("#a7ec542d"),
  all-keys.inline-code-color: rgb("#004cd9b3"),
)

#let info-check(info: (:)) = {
  for kv in info {
    let key = kv.at(0)
    assert(key in all-keys, message: key + "don't exist in all-keys")
  }

  for key in all-keys{
    assert(key.at(0) in all-key-and-default-value, message: key.at(0) + "don't exist in all-key-and-default-value")
    if not(key.at(0) in info) {
      info.insert(key.at(0), all-key-and-default-value.at(key.at(0)))
    }
  }
  return info
}