import merda, std;
extern(C):
Value merda_to_str(Value[] args, bool is_arr = 0) {
  auto s = is_arr? "[" : "";
  foreach (i, arg; args) {
    if (is_arr && i > 0) s ~= ", "; // HOW DO YOU LIKE THAT HUAUHUAHUHUUHAUHA
    s ~= arg.t==T_INT? arg.l.to!string : arg.t==T_STR? (is_arr?'\"'~arg.s~'\"':arg.s)
                     : arg.t==T_ARR? merda_to_str(arg.a, true).s : "nil";
  }
  return Value(is_arr? s ~ "]" : s);
}
Value merda_to_int(Value[] args) {
  if (args.length != 1 || args[0].t != T_STR || !args[0].s.isNumeric)
    merda.error("to_int failed to parse number");
  return Value(args[0].s.to!long);
}
Value merda_write(Value[] args) {
  merda_to_str(args).s.write;
  return Value(T_NIL);
}
Value merda_read(Value[] args) {
  merda_write(args);
  return Value(readln.strip);
}
Value merda_read_file(Value[] args) {
  if (args.length != 1 || args[0].t != T_STR) merda.error("read_file expected string");
  if (!args[0].s.exists) merda.error("could not read file '%s'".format(args[0].s));
  return Value(args[0].s.readText);
}
Value merda_write_file(Value[] args) {
  if (args.length != 2 || args[0].t != T_STR || args[1].t != T_STR)
    merda.error("write_file expected (string, string)");
  try std.file.write(args[0].s, args[1].s);
  catch (Exception _) return Value(false);
  return Value(true);
}
Value merda_append(Value[] args) {
  if (args.length < 2 || ![T_STR,T_ARR].canFind(args[0].t)) 
    merda.error("append expected array");
  if (args[0].t == T_ARR) args[0].a ~= args[1]; 
  else args[0].s ~= merda_to_str(args[1..$]).s;
  return args[0];
}
Value merda_pop(Value[] args) {
  if (args.length != 1 || ![T_STR,T_ARR].canFind(args[0].t))
    merda.error("pop expected array");
  auto res = args[0].t==T_ARR? args[0].a[$-1] : Value(args[0].s[$-1]~"");
  if (args[0].t == T_ARR) args[0].a.popBack; else args[0].s.popBack;
  return res;
}
Value merda_len(Value[] args) {
  if (args.length != 1 || ![T_STR,T_ARR].canFind(args[0].t))
    merda.error("len expected array");
  return Value(args[0].t==T_ARR? args[0].a.length : args[0].s.length);
}

