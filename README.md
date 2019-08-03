# x86prime

A few tools for our x86 subset, x86prime, known as just "prime"

## Prerequisites

Install ocaml and opam. This installs the default compiler version for the system,
which may not be recent enough. Upgrade this to version 4.07, Then use opam to
install menhir and ocamlbuild.

On debian based linux this is
~~~
> sudo apt install ocaml opam
> opam init -a
~~~
On some systems, the default ocaml version is too old. Use "ocaml --version"
to find which version you have. If you have something before 4.05.0, you need
to upgrade. Latest version is 4.07.0. To upgrade do:
~~~
> opam switch 4.07.0
[at this point you may be asked to run "eval `opam config env`" - do it]
~~~
On some systems, this is not enough, and we recommend that you exit your shell,
then restart it before proceeding
~~~
> opam install menhir ocamlbuild
~~~

## Building

The script "buildall.sh" will build 4 tools:

 * primify, a tool which translates real x86 assembler into prime assembler
 * prasm, the assembler, a tool which encodes prime assembler into a format known as "hex"
 * prun, a tool which reads hex files and runs them
 * prerf, like prun, but collect performance statistics

~~~
> ./builall.sh
~~~

If by accident you have built part of the program using an old version, you
may get an error during build indicating a version problem with part of the
project. If this happens, remove the "_build" subdirectory.

And build again.

## Generating x86 assembler

x86 assembler is in files with suffix ".s"

You can write one yourself. Or generate one from a program written in "C"
using a C-compiler.

~~~
> gcc -S -Og my_program.c
~~~

## Translating x86 into prime (x86prime)

The "./primify" program will translate an x86 assembler source file into
correspondingly named ".prime" files.

~~~
> ./primify my_program.s
~~~

This results in a new file, "my_program.prime"

## Encoding into hex format

The simulators cannot directly read the symbolic prime assembler. You need to
assemble it into hex-format. Use

~~~
> ./prasm my_program.prime
~~~

This produces "my_program.hex", which can be inspected to learn how the prime
program is encoded in numbers.

It also produces "my_program.sym", which is a list of symbols. This is used by
the simulator to allow you to pick which part of the code to execute.

## Running

Programs are simulated by "./prun"

~~~
> ./prun my_program.hex my_start_function
~~~

Here, the label "my_start_function" must have been defined by the original ".prime"
program.

Without more options, the simulation is silent. To see what happens, add "-show" option

Sit back, relax and watch the blinkenlights.

## Generating a tracefile

A tracefile records all changes to memory and register made by your program.
You request a tracefile by the "-tracefile" option:

~~~
> ./prun my_program.s my_start_function -tracefile prog.trc
~~~


## Limitations to cross-assembling

The translation from x86 to prime is not perfect.

 * When gcc optimizes heavily ("-O2, -O3"), the code patterns generated will not
   be translated correctly. In most cases primify will stop with an exception. 
   We believe "-Og" to be working reasonably well, so stick to that.

 * When gcc needs to use almost all registers in a function, translation will either fail
   or just be incorrect.

 * Using combinations of signed and unsigned longs may not be handled correctly.

 * Using constants which cannot be represented in 32-bit 2-complement form
   may not be handled correctly.

 * Larger "switch" statements can not be translated

In short, we advise you to check the translation result for correctness instead
of blindly trusting it.
