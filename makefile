file_name := "从零开始的分布式数据库生活.pdf"

.PHONY: w c f font

w:
	typst w main.typ ${file_name} --font-path ./fonts/
	
c:
	typst c main.typ ${file_name} --font-path ./fonts/

f:
	typstyle format-all ./

font:
	python3 ./fonts/download.py --proxy