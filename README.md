# Merda

Tiny interpreter in ~400 lines of code, made as a little exercise.
Merda literally means `shit`, reflecting the quality of the code.

This branch has a separate parser, a tree-walking interpreter, and an additional `map` type.
thus adding an extra ~100 lines of code. (See branch `main` for the original).

## Compiling

Dependencies: make, a D compiler (only tested with dmd and ldc).

Compile with:
```sh
make
# default compiler is dmd, to use ldc do:
make DC=ldc2
```

## Features

* Functions;
* Comments with `#`;
* Local and global variables;
* Importing files and external functions;
* Integers, strings, arrays and maps (+ lua-style `nil`);
* Basic control-flow (`if`, `elif`, `else`, `while`, `break`, `continue` and `return`);
* Basic arithmetic operations (`+`, `-`, `*` and `/`);
* Simple comparision operations (`==`, `!=`, `<`, `>`, `<=`, `>=`, `and` and `or`);
* Tiny optional core library (~70 lines of code);
* Very simple error reporting;

## Example

```
# load the 'write' function from the local DLL
extern("./lib.so", "write")

write("Hello, World!\n")
```

* See [these examples here](/examples/).

