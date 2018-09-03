# x86prime

fairly limited x86 to x86' translator

## Prerequisites

Install ocaml and opam. Then use opam to install menhir.

On debian based linux this is
~~~
> sudo apt install ocaml opam
> opam install menhir
~~~

## Building

Use ocamlbuild to build an executable

~~~
> ocamlbuild -use.menhir x86prime.native
~~~

## Testing

Use gcc to compile your favourite C program to assembler at
optimization level "-Og", then call x86prime with -f, specifying
the assembly file:

~~~
> gcc -S -Og my_amazing_program.c
> x86prime.native -f my_amazing_program.s
~~~

Sit back, relax and watch the blinkenlights.

