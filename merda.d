import std.stdio, std.ascii, std.array, std.conv, std.file, std.string, std.algorithm,
       core.sys.posix.dlfcn, core.stdc.stdlib : exit;
struct Range { ulong start, end; }
enum : ulong { NONE, RETURN, BREAK, CONTINUE }
enum : ubyte { T_NIL, T_INT, T_STR, T_ARR }
struct Value {
  ubyte t; union { long l; string s; Value[] a; }
  this(ubyte t_) { t=t_; }
  this(long l_) { t=T_INT,l=l_; }
  this(bool b_) { this(b_.to!long); }
  this(string s_) { t=T_STR,s=s_; }
  this(Value[] a_) { t=T_ARR,a=a_; }
  bool isTrue() => t==T_INT? l!=0 : t==T_STR? s.length!=0 : t==T_ARR? a.length!=0 : false;
  bool opEquals(Value o) =>
    t==o.t? (t==T_INT? l==o.l : t==T_STR? s==o.s : t==T_ARR? a==o.a : true) : false;
}
struct Func { Range range; string[] args; Value[string] vars; }
string[] tokenize(string text) {
  string[] res; string tok; int is_blk;
  foreach (chr; text) {
    if (is_blk == 2 && chr == '\n') is_blk = 0, tok = "";
    else if (is_blk == 2) continue;
    if (!is_blk && chr.isWhite) {
      if (!is_blk && tok.strip.length) res ~= tok, tok = "";
      continue;
    } else if (chr == '\"') {
      if (is_blk == 1 && tok.endsWith("\\")) {
        tok ~= chr; continue;
      }
      if (tok) res ~= tok;
      tok = is_blk? "" : ""~chr, is_blk = (is_blk)? 0 : 1;
    } else if (!is_blk && chr == '#') {
      if (tok) res ~= tok;
      tok = "", is_blk = 2;
    } else if (!is_blk && "+-*/!=<>,(){}[]".canFind(chr)) {
      if (tok) res ~= tok;
      res ~= ""~chr, tok = "";
    } else tok ~= chr;
  }
  return res.filter!(x => x.strip.length != 0).array;
}
string escapeString(string s) {
  auto r="", cs = ['n': '\n', 'r': '\r', 't': '\t', 'e': '\033'];
  for (int i = 0; i < s.length; ++i)
    if (s[i] == '\\') if (++i >= s.length) break;
                      else r ~= (s[i] in cs)? cs[s[i]] : s[i];
    else r ~= s[i];
  return r;
}
Value merda_extern(Value[] args) {
  if (args.length < 2 || args[0].t != T_STR) error("extern expects library path and func names");
  libs ~= dlopen(args[0].s.toStringz, RTLD_LAZY);
  if (libs[$-1] is null) error("could not load library '%s'".format(args[0].s));
  foreach (fn; args[1..$]) {
    extn[fn.s] = cast(Value function(Value[]))dlsym(libs[$-1], ("merda_"~fn.s).toStringz);
    auto err = dlerror();
    if (err) error(err.fromStringz.to!string);
  }
  return Value(T_NIL);
}
Value merda_import(Value[] args) {
  if (args.length != 1 || args[0].t != T_STR) error("import expects file paths");
  foreach (fl; args) {
    auto start = intp.toks.length;
    if (!fl.s.exists || fl.s.isDir) error("could not import file '%s'".format(fl.s));
    intp.toks ~= fl.s.readText.tokenize~"";
    intp.execRange(Range(start, intp.toks.length-1));
  }
  return Value(T_NIL);
}
Value merda_exit(Value[] args) {
  if (!args.length) merda_exit([Value(1)]);
  foreach (lib; libs) dlclose(lib);
  exit(cast(int)args[0].l);
}
void error(string err) {
  stderr.writefln("error: %s", err);
  merda_exit([Value(1)]);
}
Value function(Value[])[string] extn; void*[] libs; Interpreter intp;
class Interpreter {
  string[] toks;
  ulong cur, loop_out;
  Func[string] funs; Func *cfun;
  this(string[] t, string[] args) {
    toks = t~"", cur = 0, funs["<GLOBAL>"] = Func(Range(0, toks.length-1));
    funs["<GLOBAL>"].vars["args"] = Value(args.map!(a => Value(a)).array);
    extn = ["extern": &merda_extern, "import": &merda_import, "exit": &merda_exit];
  }
  void consume(string tok) {
    if (toks[cur++] != tok) error("missing '%s'".format(tok));
  }
  Value exec() => execFunc(funs["<GLOBAL>"]);
  Value execRange(Range range) {
    auto prev = cur, res = Value(T_NIL); cur = range.start;
    while (cur < range.end) {
      if (loop_out != NONE) break;
      res = execExpr;
    }
    cur = prev;
    return res;
  }
  Value execFunc(Func fn, Value[] args = []) {
    auto pfun = cfun; cfun = &fn;
    foreach (i, arg; args) {
      if (i >= cfun.args.length) break;
      cfun.vars[cfun.args[i]] = arg;
    }
    auto res = execRange(cfun.range);
    loop_out = NONE, cfun = pfun;
    return res;
  }
  Value execWord(string word) {
    if (toks[cur] == "=" && toks[cur+1] != "=") {
      ++cur; auto e = execExpr;
      return cfun.vars[word] = e;
    } else if (toks[cur] == "(") {
      Value[] args;
      do if (toks[++cur] == ")") break; else args ~= execExpr;
      while (toks[cur] == ",");
      consume(")");
      if (word in funs) return execFunc(funs[word], args);
      else if (word in extn) return extn[word](args);
      error("unknown function '%s'".format(word)); assert(0);
    }
    if (word in cfun.vars) return cfun.vars[word];
    else if (word in funs["<GLOBAL>"].vars) return funs["<GLOBAL>"].vars[word];
    error("unknown variable '%s'".format(word)); assert(0);
  }
  Value execExpr(int p = 0) {
    auto precs = [["and","or"],["<",">","!","="],["+","-"],["*","/"]];
    auto l = (p==3)? execPrimary() : execExpr(p+1);
    while (precs[p].canFind(toks[cur])) {
      auto op = toks[cur++];
      if (p == 1 && toks[cur] == "=") op ~= toks[cur++];
      l = execBinary(op, l, (p==3)? execPrimary() : execExpr(p+1));
    }
    return l;
  }
  Range makeRange() {
    auto start=cur+1, lvl=0;
    consume("{");
    do {
      if (toks[cur] == "{") ++lvl;
      if (toks[cur] == "}" && --lvl < 0) return Range(start, cur++);
    } while (++cur < toks.length);
    consume("}"); assert(0);
  }
  Value makeFunc(string name) {
    Func fn; ++cur;
    do if (toks[++cur] == ")") break; else fn.args ~= toks[cur++];
    while (toks[cur] == ",");
    consume(")");
    fn.range = makeRange, funs[name] = fn;
    return Value(T_NIL);
  }
  Value execIf() {
    struct IfCond { Value cond; Range range; }
    IfCond[] conds;
    do ++cur, conds ~= IfCond(execExpr, makeRange); while (toks[cur] == "elif");
    if (toks[cur] == "else") ++cur, conds ~= IfCond(Value(true), makeRange);
    foreach (c; conds) if (c.cond.isTrue) return execRange(c.range);
    return Value(T_NIL);
  }
  Value execWhile() {
    auto pos = ++cur, cond = execExpr, range = makeRange, res = Value(T_NIL);
    while (cond.isTrue) {
      res = execRange(range);
      if ([RETURN, BREAK].canFind(loop_out)) break;
      loop_out = NONE, cur = pos, cond = execExpr;
    }
    if (loop_out == BREAK) loop_out = NONE;
    cur = range.end+1;
    return res;
  }
  Value execReturn() {
    auto res = toks[++cur] == "}"? Value(T_NIL) : execExpr;
    loop_out = RETURN;
    return res;
  }
  Value execBreak(bool is_break) {
    loop_out = is_break? BREAK : CONTINUE;
    return Value(T_NIL);
  }
  Value execArray() {
    Value[] arr;
    do if (toks[++cur] == "]") break; else arr ~= execExpr;
    while (toks[cur] == ",");
    consume("]");
    return Value(arr);
  }
  Value execArrayIdx(Value arr) {
    if (![T_STR, T_ARR].canFind(arr.t)) error("can only index arrays");
    consume("[");
    auto idx = execExpr, len = arr.t==T_STR? arr.s.length : arr.a.length;
    if (idx.t!=T_INT || (idx.l<0 || idx.l>=len)) error("index out of range");
    consume("]");
    if (toks[cur] == "=" && toks[cur+1] != "=") {
      if (arr.t!=T_ARR) error("cannot assign to string index");
      ++cur;
      return arr.a[idx.l] = execExpr;
    }
    return arr.t==T_STR? Value(""~arr.s[idx.l]) : arr.a[idx.l];
  }
  Value execTerm() {
    switch (toks[cur]) {
    case "(":
      ++cur; auto res = execExpr;
      consume(")");
      return res;
    case "-": case "+": case "!":
      auto op = toks[cur++], val = execPrimary;
      return op=="!"? Value(!val.isTrue) : execBinary(op, Value(0), val);
    case "[": return execArray();
    case "nil": ++cur; return Value(T_NIL);
    case "func": return makeFunc(toks[++cur]);
    case "if": return execIf();
    case "while": return execWhile();
    case "return": return execReturn();
    case "break": case "continue": return execBreak(toks[cur++]=="break");
    default:
      if (toks[cur].isNumeric) return Value(toks[cur++].to!long);
      else if (toks[cur].startsWith("\"")) 
        return Value(toks[cur++][1..$].escapeString());
      return execWord(toks[cur++]);
    }
  }
  Value execPrimary() {
    auto res = execTerm;
    while (toks[cur] == "[") res = execArrayIdx(res);
    return res;
  }
  Value execBinary(string op, Value l, Value r) {
    if (op=="==") return Value(l == r); else if (op=="!=") return Value(l != r);
    else if (op=="and") return Value(l.isTrue && r.isTrue);
    else if (op=="or") return Value(l.isTrue || r.isTrue);
    else if (l.t != T_INT || r.t != T_INT) error("'%s' expected int".format(op));
    switch (op) {
    case "<": return Value(l.l <  r.l); case "<=": return Value(l.l <= r.l);
    case ">": return Value(l.l >  r.l); case ">=": return Value(l.l >= r.l);
    case "+": return Value(l.l +  r.l); case "-":  return Value(l.l -  r.l);
    case "*": return Value(l.l *  r.l); case "/":  return Value(l.l /  r.l);
    default: error("unknown '%s'".format(op)); assert(0);
    }
  }
}
void main(string[] args) {
  if (args.length < 2) {
    stderr.writefln("usage: %s <input>", args[0]);
    return;
  }
  intp = new Interpreter(args[1].readText.tokenize, args[1..$]);
  intp.exec;
  merda_exit([Value(0)]);
}
