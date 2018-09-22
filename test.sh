echo "Cleaning and making test files..."
cd tests/
rm -f *.s
cf=*.c
gcc -S -Og ${cf}

echo "Building x86prime..."
cd ..
ocamlbuild -use-menhir x86prime.native

echo "Simulating test files..."
for af in tests/*.s; do
    ./x86prime.native -f "$af" -asm -list
done
