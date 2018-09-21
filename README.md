# x86prime

fairly limited x86 to x86' translator

## Prerequisites

Install ocaml and opam. Then use opam to install menhir and ocamlbuild.

On debian based linux this is
~~~
> sudo apt install ocaml opam
> opam install menhir ocamlbuild
~~~

## Building

Use ocamlbuild to build an executable

~~~
> ocamlbuild -use.menhir x86prime.native
~~~

## Assembling

Write a x86prime program and put it in a file, say prog.s.
Then call x86prime with -f, specifying the assembly file, and 
-asm to assemble to a memory image. Add -list if you want to
see a printout of the assembly.

~~~
> x86prime.native -f prog.s -asm -list
~~~

## Cross-assembling

Use gcc to compile your favourite C program to assembler at
optimization level "-Og", then call x86prime with -f, specifying
the assembly file, and -txl to ask for translation from ordinary 
x86 assembly:

~~~
> gcc -S -Og my_amazing_program.c
> x86prime.native -f my_amazing_program.s -asm -list -txl
~~~

## Running

Call x86prime with -run, specifying the entry point for the simulation:

~~~
> gcc -S -Og my_amazing_program.c
> x86prime.native -f my_amazing_program.s -asm -txl -show -run my_little_function
~~~

Sit back, relax and watch the blinkenlights.

