# Merda

Tiny interpreter in ~300 lines of code, made as a little exercise.
Merda literally means `shit`, reflecting the quality of the code.

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
* Integers, strings and arrays (+ lua-style `nil`);
* Basic control-flow (`if`, `elif`, `else`, `while`, `break`, `continue` and `return`);
* Basic arithmetic operations (`+`, `-`, `*` and `/`);
* Simple comparision operations (`==`, `!=`, `<`, `>`, `<=`, `>=`, `and` and `or`);
* Tiny optional core library (~55 lines of code);
* Very simple error reporting;

## Example

* See [this example file](/example.mr) and [this other file](/count-lines.mr).

