ocamlbuild -use-menhir primify.native
ocamlbuild -use-menhir prasm.native
ocamlbuild -use-menhir prun.native
ocamlbuild -use-menhir prerf.native
mkdir -p bin
pushd bin
ln -fs ../primify.native primify
ln -fs ../prasm.native prasm
ln -fs ../prun.native prun
ln -fs ../prerf.native prerf
popd
