.PHONY: w c f font


w:
	python3 ./typst-book-template/op.py w
	
c:
	python3 ./typst-book-template/op.py c

f:
	python3 ./typst-book-template/op.py f

font:
	python3 ./typst-book-template/fonts/download.py --proxy
