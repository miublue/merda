#include <raylib.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// these are some very VERY shit bindings i wrote whilst drunk
// but it works for me so ig its aight lmfao lul lel lol lmao
// i only tested ts with gcc for now mai bad ayy
enum { T_NIL, T_INT, T_STR, T_ARR };
typedef struct String { size_t length; char *data; } String;
typedef struct Array { size_t length; struct Value *data; } Array;
typedef struct Value { uint8_t t; union { int64_t l; String s; Array a; }; } Value;

char *stringToPointer(String a);
bool stringIsEquals(String a, String b);
bool arrayIsEquals(Array a, Array b);
bool valueIsTrue(Value a);
bool valueIsEquals(Value a, Value b);

bool valueIsTrue(Value a) {
  return a.t==T_INT? a.l!=0 : a.t==T_STR? a.s.length!=0 : a.t==T_ARR? a.a.length!=0 : false;
}

bool valueIsEquals(Value a, Value b) {
  return a.t==b.t? (a.t==T_INT? a.l==b.l : a.t==T_STR? stringIsEquals(a.s, b.s) : a.t==T_ARR? arrayIsEquals(a.a, b.a) : true) : false;
}

char *stringToPointer(String a) {
  a.data[a.length] = 0;
  return a.data;
}

bool stringIsEquals(String a, String b) {
  return a.length == b.length && strncmp(a.data, b.data, a.length) == 0;
}

bool arrayIsEquals(Array a, Array b) {
  if (a.length != b.length) return false;
  for (size_t i = 0; i < a.length; ++i) if (!valueIsEquals(a.data[i], b.data[i])) return false;
  return true;
}

Value merda_InitWindow(Array args) {
  InitWindow(args.data[0].l, args.data[1].l, stringToPointer(args.data[2].s));
  return (Value) { .t = T_NIL };
}

Value merda_CloseWindow(Array args) {
  CloseWindow();
  return (Value) { .t = T_NIL };
}

Value merda_WindowShouldClose(Array args) {
  return (Value) { .t = T_INT, .l = WindowShouldClose() };
}

Value merda_SetTargetFPS(Array args) {
  SetTargetFPS(args.data[0].l);
  return (Value) { .t = T_NIL };
}

Value merda_BeginDrawing(Array args) {
  BeginDrawing();
  return (Value) { .t = T_NIL };
}

Value merda_EndDrawing(Array args) {
  EndDrawing();
  return (Value) { .t = T_NIL };
}

static Color parse_color(Value val) {
  if (val.t == T_ARR)
    return (Color) { .r = val.a.data[0].l, .g = val.a.data[1].l, .b = val.a.data[2].l, .a = val.a.data[3].l };
  return (Color) {
    .r = (val.l & 0xff000000) >> 24, .g = (val.l & 0x00ff0000) >> 16,
    .b = (val.l & 0x0000ff00) >>  8, .a = (val.l & 0x000000ff) >>  0, };
}

Value merda_ClearBackground(Array args) {
  Color col = parse_color(args.data[0]);
  ClearBackground(col);
  return (Value) { .t = T_NIL };
}

