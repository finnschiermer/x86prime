ocamlbuild -use-menhir primify.native
ocamlbuild -use-menhir hexify.native
ocamlbuild -use-menhir prun.native
ocamlbuild -use-menhir prerf.native
ln -fs primify.native primify
ln -fs hexify.native hexify
ln -fs prun.native prun
ln -fs prerf.native prerf
