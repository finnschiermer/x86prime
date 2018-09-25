# x86prime

fairly limited x86 to x86' translator

## Prerequisites

Install ocaml and opam. This installs the default compiler version for the system,
which may not be recent enough. Upgrade this to version 4.07, Then use opam to
install menhir and ocamlbuild.

On debian based linux this is
~~~
> sudo apt install ocaml opam
> opam switch 4.07.0
< [at this point you may be asked to run "eval `opam config env`" - do it]
> opam install menhir ocamlbuild
~~~

## Building

Use ocamlbuild to build an executable

~~~
> ocamlbuild -use-menhir x86prime.native
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

## Limitations to cross-assembling

The translation from x86 to x86 is not perfect.

 * When gcc optimizes heavily ("-O2, -O3"), the code patterns generated will not
   be translated correctly. In most cases x86prime will stop with a "Cannot unify at.."
   exception. We believe "-Og" to be working reasonably well, so stick to that.

 * When gcc needs to use almost all registers, translation will either fail
   or just be incorrect. It will fail if gcc needs to use %r14 or %r15, and
   it will likely be incorrect if gcc needs to access the stack with a combination
   of push, pop and movq instead of just push and pop.

 * Using combinations of signed and unsigned longs may not be handled correctly.

 * Using constants which cannot be represented in 32-bit 2-complement form
   may not be handled correctly.

In short, we advise you to check the translation result for correctness instead
of blindly trusting it.
