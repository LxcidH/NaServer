all:
	mkdir build
	nasm -f elf64 src/main.asm -o build/main.o
	ld build/main.o -o http-server

clean:
	rm -rf build
