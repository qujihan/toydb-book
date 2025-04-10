#import "../book-template/book.typ":*

#let format-title-and-path(title, path) = { title + text(font: "Maple Mono NF", " (" + path + ")") }
#let code(title, path) = {
  code-figure(format-title-and-path(title, path), raw(read(path), block: true, lang: "C++"))
}