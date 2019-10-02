#!/bin/bash
ocamlbuild -use-menhir primify.native
ocamlbuild -use-menhir prasm.native
ocamlbuild -use-menhir prun.native
ocamlbuild -use-menhir prerf.native
mkdir -p bin
pushd bin
ln -fsr ../primify.native primify
ln -fsr ../prasm.native prasm
ln -fsr ../prun.native prun
ln -fsr ../prerf.native prerf
popd
