import std.stdio, std.ascii, std.array, std.conv,
       std.file, std.string, std.algorithm,
       core.stdc.stdlib : exit;

enum : ubyte { NONE, RETURN, BREAK, CONTINUE }
enum : ubyte { T_NIL, T_INT, T_STR, T_ARR }
struct Range { ulong start, end; }
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

string[] parse(string text) {
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
  auto r="", cs = ['n': '\n', 'r': '\r', 't': '\t'];
  for (int i = 0; i < s.length; ++i)
    if (s[i] == '\\') if (++i >= s.length) break;
                      else r ~= (s[i] in cs)? cs[s[i]] : s[i];
    else r ~= s[i];
  return r;
}
Value extn_to_str(Value[] args, bool is_arr = 0) {
  auto s = is_arr? "[" : "";
  foreach (i, arg; args) {
    if (is_arr && i > 0) s ~= ", "; // HOW DO YOU LIKE THAT HUAUHUAHUHUUHAUHA
    s ~= arg.t==T_INT? arg.l.to!string : arg.t==T_STR? (is_arr?'\"'~arg.s~'\"':arg.s)
                     : arg.t==T_ARR? extn_to_str(arg.a, true).s : "nil";
  }
  return Value(is_arr? s ~ "]" : s);
}
Value extn_to_int(Value[] args) {
  if (args.length != 1 || args[0].t != T_STR || !args[0].s.isNumeric)
    error("to_int failed to parse number");
  return Value(args[0].s.to!long);
}
Value extn_print(Value[] args) {
  extn_to_str(args).s.write;
  return Value(T_NIL);
}
Value extn_read(Value[] args) {
  extn_print(args);
  return Value(readln.strip);
}
Value extn_append(Value[] args) {
  if (args.length < 2 || ![T_STR,T_ARR].canFind(args[0].t)) 
    error("append expected array");
  if (args[0].t == T_ARR) args[0].a ~= args[1]; 
  else args[0].s ~= extn_to_str(args[1..$]).s;
  return args[0];
}
Value extn_pop(Value[] args) {
  if (args.length != 1 || ![T_STR,T_ARR].canFind(args[0].t))
    error("pop expected array");
  auto res = args[0].t==T_ARR? args[0].a[$-1] : Value(args[0].s[$-1]~"");
  if (args[0].t == T_ARR) args[0].a.popBack; else args[0].s.popBack;
  return res;
}
Value extn_len(Value[] args) {
  if (args.length != 1 || ![T_STR,T_ARR].canFind(args[0].t))
    error("len expected array");
  return Value(args[0].t==T_ARR? args[0].a.length : args[0].s.length);
}
void error(string err) {
  stderr.writefln("error: %s", err);
  exit(1);
}
class Interpreter {
  string[] toks;
  ulong cur;
  ubyte loop_out;
  Value[string] globs;
  Func[string] funs;
  Func *cfun;
  Value function(Value[])[string] extn;
  this(string[] t) {
    toks = t~"", cur = 0, funs["<GLOBAL>"] = Func(Range(0, toks.length-1));
    extn = [
      "to_str": (a) => extn_to_str(a),
      "to_int": &extn_to_int,
      "print":  &extn_print,
      "read":   &extn_read,
      "append": &extn_append,
      "pop":    &extn_pop,
      "len":    &extn_len,
    ];
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
      if (cfun == &funs["<GLOBAL>"]) return globs[word] = e;
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
    else if (word in globs) return globs[word];
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
    ++cur; auto res = execExpr;
    loop_out = RETURN;
    return res;
  }
  Value execBreak(bool is_break) {
    loop_out = is_break? BREAK : CONTINUE;
    return Value(T_NIL);
  }
  Value execArray() {
    Value[] arr;
    do {
      if (toks[++cur] == "]") break;
      arr ~= execExpr;
    } while (toks[cur] == ",");
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
      auto val = execExpr;
      return arr.a[idx.l] = val;
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
    case "<":  return Value(l.l <  r.l); case "<=": return Value(l.l <= r.l);
    case ">":  return Value(l.l >  r.l); case ">=": return Value(l.l >= r.l);
    case "+":  return Value(l.l +  r.l); case "-":  return Value(l.l -  r.l);
    case "*":  return Value(l.l *  r.l); case "/":  return Value(l.l /  r.l);
    default: error("unknown '%s'".format(op)); assert(0);
    }
  }
}
void main(string[] args) {
  if (args.length < 2) {
    stderr.writefln("usage: %s <input>", args[0]);
    return;
  }
  new Interpreter(args[1].readText.parse).exec;
}
