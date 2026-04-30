# Merda

Tiny interpreter in ~300 lines of code, made as a little exercise.
Merda literally means `shit`, reflecting the quality of the code.

## Compiling
Dependencies: `make`, a D compiler (only tested with dmd and ldc).

Compile with:
```sh
dmd merda.d
# or with ldc
ldc2 merda.d
```

## Features

* Functions;
* Comments with `#`;
* Local and global variables;
* Integers, strings and arrays (+ lua-style `nil`);
* Basic control-flow (`if`, `else`, `while`, `break`, `continue` and `return`);
* Basic arithmetic operations (`+`, `-`, `*` and `/`);
* Simple comparision operations (`==`, `!=`, `<`, `>`, `<=`, `>=`, `and` and `or`);
* Tiny core library (`print`, `read`, `to_int`, `to_str`, `append`, `pop` and `len`);
* Very simple error reporting;

## Example

* See [this example file](/example.mr).

