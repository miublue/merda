import std, core.sys.posix.dlfcn, core.stdc.stdlib : exit;
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
  bool opEquals(Value o) => t==o.t? (t==T_INT? l==o.l : t==T_STR? s==o.s : t==T_ARR? a==o.a : true) : false;
}
string[] tokenize(string text) {
  string[] res; string tok; int is_blk;
  foreach (chr; text) {
    if (is_blk == 2 && chr == '\n') is_blk = 0, tok = "";
    else if (is_blk == 2) continue;
    if (!is_blk && std.ascii.isWhite(chr)) {
      if (!is_blk && tok.strip.length) res ~= tok, tok = "";
      continue;
    } else if (chr == '\"') {
      if (is_blk == 1 && tok.endsWith("\\")) { tok ~= chr; continue; }
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
    if (s[i] == '\\') if (++i >= s.length) break; else r ~= (s[i] in cs)? cs[s[i]] : s[i];
    else r ~= s[i];
  return r;
}
string findFile(string s) {
  if (s.absolutePath.exists) return s.absolutePath;
  auto p = thisExePath.split('/')[0..$-1].join('/') ~ '/' ~ s;
  return p.absolutePath;
}
Value merda_extern(Value[] args) {
  if (args.length < 2 || args[0].t != T_STR) error("extern expects library path and func names");
  auto path = args[0].s.expandTilde.findFile;
  libs ~= dlopen(path.toStringz, RTLD_LAZY);
  if (libs[$-1] is null) error("could not load library '%s'".format(path));
  foreach (fn; args[1..$]) {
    extn[fn.s] = cast(Value function(Value[]))dlsym(libs[$-1], ("merda_"~fn.s).toStringz);
    auto err = dlerror();
    if (err) error(err.fromStringz.to!string);
  }
  return Value(T_NIL);
}
Value merda_import(Value[] args) {
  foreach (path; args) {
    if (path.t != T_STR) error("import expects file paths");
    auto file = path.s.expandTilde.findFile;
    if (!file.exists || file.isDir) error("could not import file '%s'".format(path.s));
    auto i = new Interpreter(new Parser(file.readText.tokenize~"").parse);
    i.exec;
    foreach (func; i.funs.byKeyValue) intp.funs[func.key] = func.value;
    foreach (glob; i.funs["<GLOBAL>"].vars.byKeyValue) intp.funs["<GLOBAL>"].vars[glob.key] = glob.value;
  }
  return Value(T_NIL);
}
Value merda_exit(Value[] args) {
  if (!args.length) merda_exit([Value(1)]);
  foreach (lib; libs) if (lib !is null) dlclose(lib);
  exit(cast(int)args[0].l);
}
void error(string err) {
  stderr.writefln("error: %s", err);
  merda_exit([Value(1)]);
}
Value function(Value[])[string] extn; void*[] libs; Interpreter intp;
enum NodeType {
  LOAD_CONST, MAKE_FUNC, CALL_FUNC, UNARY, BINARY, WHILE,
  IFELSE, RETURN, BLOCK, VARIABLE, MAKE_ARRAY, ARRAY_INDEX,
}
struct NodeIfCond { Node* cond, expr; }
struct NodeVariable { string name; Node* expr; }
struct NodeMakeFunc { string name; string[] args; Node* expr; }
struct NodeCallFunc { string name; Node*[] args; }
struct NodeBinary { string op; Node* left, right; }
struct NodeUnary { string op; Node* expr; }
struct NodeReturn { ulong ret_type; Node* expr; }
struct NodeArrayIndex { Node* array, index, expr; }
struct Node {
  NodeType t;
  union {
    Value load_const;
    NodeVariable variable;
    NodeMakeFunc make_func;
    NodeCallFunc call_func;
    NodeBinary binary;
    NodeUnary unary;
    NodeIfCond[] ifelse;
    NodeReturn ret;
    Node*[] block;
    NodeArrayIndex array_index;
  };
}
class Parser {
  string[] toks; ulong cur;
  this(string[] t) {
    toks = t~"", cur = 0;
  }
  void consume(string tok) {
    if (toks[cur++] != tok) error("missing '%s'".format(tok));
  }
  Node*[] parse() {
    Node*[] ast;
    while (cur < toks.length && toks[cur] != "") ast ~= genExpr;
    return ast;
  }
  Node* genWord(string word) {
    Node *expr = null;
    if (toks[cur] == "(") {
      Node*[] args;
      do if (toks[++cur] == ")") break; else args ~= genExpr;
      while (toks[cur] == ",");
      consume(")");
      return new Node(NodeType.CALL_FUNC, call_func: NodeCallFunc(word, args));
    } else if (toks[cur] == "=" && toks[cur+1] != "=") ++cur, expr = genExpr;
    return new Node(NodeType.VARIABLE, variable: NodeVariable(word, expr));
  }
  Node* genExpr(int p = 0) {
    auto precs = [["and","or"],["<",">","!","="],["+","-"],["*","/"]];
    auto l = (p==3)? genPrimary() : genExpr(p+1);
    while (precs[p].canFind(toks[cur])) {
      auto op = toks[cur++];
      if (p == 1 && toks[cur] == "=") op ~= toks[cur++];
      l = new Node(NodeType.BINARY, binary: NodeBinary(op, l, (p==3)? genPrimary() : genExpr(p+1)));
    }
    return l;
  }
  Node* genBlock() {
    Node*[] block;
    consume("{");
    while (cur < toks.length && !["}", ""].canFind(toks[cur])) block ~= genExpr;
    consume("}");
    return new Node(NodeType.BLOCK, block: block);
  }
  Node* genMakeFunc(string name) {
    NodeMakeFunc func; ++cur;
    do if (toks[++cur] == ")") break; else func.args ~= toks[cur++];
    while (toks[cur] == ",");
    consume(")");
    func.name = name, func.expr = genExpr;
    return new Node(NodeType.MAKE_FUNC, make_func: func);
  }
  Node* genIfElse() {
    NodeIfCond[] ifelse;
    do ++cur, ifelse ~= NodeIfCond(genExpr, genExpr); while (toks[cur] == "elif");
    if (toks[cur] == "else")
      ++cur, ifelse ~= NodeIfCond(new Node(NodeType.LOAD_CONST, load_const: Value(true)), genExpr);
    return new Node(NodeType.IFELSE, ifelse: ifelse);
  }
  Node* genWhile() {
    ++cur;
    return new Node(NodeType.WHILE, ifelse: [NodeIfCond(genExpr, genExpr)]);
  }
  Node* genReturn() {
    auto res = toks[++cur] == "}"? null : genExpr;
    return new Node(NodeType.RETURN, ret: NodeReturn(RETURN, res));
  }
  Node* genBreak(bool is_break) => new Node(NodeType.RETURN, ret: NodeReturn(is_break? BREAK : CONTINUE, null));
  Node* genMakeArray() {
    Node*[] arr;
    do if (toks[++cur] == "]") break; else arr ~= genExpr;
    while (toks[cur] == ",");
    consume("]");
    return new Node(NodeType.MAKE_ARRAY, block: arr);
  }
  Node* genArrayIndex(Node* arr) {
    consume("[");
    auto idx = NodeArrayIndex(array: arr, index: genExpr, expr: null);
    consume("]");
    if (toks[cur] == "=" && toks[cur+1] != "=") ++cur, idx.expr = genExpr;
    return new Node(NodeType.ARRAY_INDEX, array_index: idx);
  }
  Node* genTerm() {
    switch (toks[cur]) {
    case "(":
      ++cur; auto res = genExpr;
      consume(")");
      return res;
    case "-": case "+": case "!":
      return new Node(NodeType.UNARY, unary: NodeUnary(toks[cur++], genPrimary));
    case "{": return genBlock();
    case "[": return genMakeArray();
    case "nil": ++cur; return new Node(NodeType.LOAD_CONST, load_const: Value(T_NIL));
    case "func": return genMakeFunc(toks[++cur]);
    case "if": return genIfElse();
    case "while": return genWhile();
    case "return": return genReturn();
    case "break": case "continue": return genBreak(toks[cur++]=="break");
    default:
      if (toks[cur].isNumeric) return new Node(NodeType.LOAD_CONST, load_const: Value(toks[cur++].to!long));
      else if (toks[cur].toLower.startsWith("0x"))
        return new Node(NodeType.LOAD_CONST, load_const: Value(toks[cur++][2..$].to!long(16)));
      else if (toks[cur].startsWith("\""))
        return new Node(NodeType.LOAD_CONST, load_const: Value(toks[cur++][1..$].escapeString()));
      return genWord(toks[cur++]);
    }
  }
  Node* genPrimary() {
    auto res = genTerm;
    while (toks[cur] == "[") res = genArrayIndex(res);
    return res;
  }
}
struct Function { string[] args; Value[string] vars; Node *body; }
class Interpreter {
  ulong loop_out; Function[string] funs; Function* cfun;
  this(Node*[] code, string[] args = []) {
    funs["<GLOBAL>"] = Function(args: [],
        vars: ["args": Value(args.map!(a => Value(a)).array)],
        body: new Node(NodeType.BLOCK, block: code));
    extn = ["extern": &merda_extern, "import": &merda_import, "exit": &merda_exit];
  }
  Value exec() => execFunc(funs["<GLOBAL>"]);
  Value execFunc(Function fn, Value[] args = []) {
    auto pfun = cfun; cfun = &fn;
    foreach (i, arg; cfun.args) cfun.vars[arg] = i<args.length? args[i] : Value(T_NIL);
    auto res = execExpr(cfun.body);
    loop_out = NONE, cfun = pfun;
    return res;
  }
  Value execExpr(Node* node) {
    final switch(node.t) {
    case NodeType.LOAD_CONST:  return node.load_const;
    case NodeType.MAKE_FUNC:   return execMakeFunc(node.make_func);
    case NodeType.CALL_FUNC:   return execCallFunc(node.call_func);
    case NodeType.UNARY:       return execUnary(node.unary);
    case NodeType.BINARY:      return execBinary(node.binary);
    case NodeType.WHILE:       return execWhile(node.ifelse[0]);
    case NodeType.IFELSE:      return execIfElse(node.ifelse);
    case NodeType.RETURN:      return execReturn(node.ret);
    case NodeType.BLOCK:       return execBlock(node.block);
    case NodeType.VARIABLE:    return execVariable(node.variable);
    case NodeType.MAKE_ARRAY:  return execMakeArray(node.block);
    case NodeType.ARRAY_INDEX: return execArrayIndex(node.array_index);
    }
  }
  Value execMakeFunc(NodeMakeFunc make_func) {
    funs[make_func.name] = Function(make_func.args, new Value[string], make_func.expr);
    foreach (arg; funs[make_func.name].args) funs[make_func.name].vars[arg] = Value(T_NIL);
    return Value(T_NIL);
  }
  Value execCallFunc(NodeCallFunc call_func) {
    auto args = call_func.args.map!(a => execExpr(a)).array;
    if (call_func.name in funs) return execFunc(funs[call_func.name], args);
    if (call_func.name in extn) return extn[call_func.name](args);
    error("function '%s' does not exist".format(call_func.name)); assert(0);
  }
  Value execVariable(NodeVariable var) {
    if (var.expr !is null) return cfun.vars[var.name] = execExpr(var.expr);
    if (var.name in cfun.vars) return cfun.vars[var.name];
    if (var.name in funs["<GLOBAL>"].vars) return funs["<GLOBAL>"].vars[var.name];
    error("variable '%s' does not exist".format(var.name)); assert(0);
  }
  Value execMakeArray(Node*[] exprs) => Value(exprs.map!(e => execExpr(e)).array);
  Value execArrayIndex(NodeArrayIndex arr) {
    auto array = execExpr(arr.array), index = execExpr(arr.index);
    if (![T_STR, T_ARR].canFind(array.t)) error("can only index arrays");
    auto len = array.t==T_STR? array.s.length : array.a.length;
    if (index.t!=T_INT || (index.l<0 || index.l>=len)) error("index out of range");
    if (arr.expr !is null) {
      if (array.t != T_ARR) error("cannot assign to string index");
      return array.a[index.l] = execExpr(arr.expr);
    }
    return array.t==T_STR? Value(""~array.s[index.l]) : array.a[index.l];
  }
  Value execReturn(NodeReturn ret) {
    loop_out = ret.ret_type;
    return (ret.expr is null)? Value(T_NIL) : execExpr(ret.expr);
  }
  Value execWhile(NodeIfCond loop) {
    auto res = Value(T_NIL);
    while (execExpr(loop.cond).isTrue) {
      res = execExpr(loop.expr);
      if (loop_out == RETURN) return res;
      else if (loop_out == BREAK) { loop_out = NONE; return res; }
      else if (loop_out == CONTINUE) { loop_out = NONE; continue; }
    }
    return res;
  }
  Value execIfElse(NodeIfCond[] ifelse) {
    foreach (cond; ifelse)
      if (execExpr(cond.cond).isTrue) return execExpr(cond.expr);
    return Value(T_NIL);
  }
  Value execBlock(Node*[] block) {
    auto res = Value(T_NIL);
    foreach (n; block) {
      res = execExpr(n);
      if (loop_out != NONE) break;
    }
    return res;
  }
  Value execUnary(NodeUnary una) {
    switch (una.op) {
    case "!": return Value(!execExpr(una.expr).isTrue);
    case "-": case "+":
      return execBinary(NodeBinary(una.op, new Node(NodeType.LOAD_CONST, load_const: Value(0)), una.expr));
    default: error("unknown operator '%s'".format(una.op)); assert(0);
    }
  }
  Value execBinary(NodeBinary bin) {
    auto l = execExpr(bin.left), r = execExpr(bin.right);
    if (bin.op=="==") return Value(l == r);
    else if (bin.op=="!=") return Value(l != r);
    else if (bin.op=="and") return Value(l.isTrue && r.isTrue);
    else if (bin.op=="or") return Value(l.isTrue || r.isTrue);
    else if (l.t != T_INT || r.t != T_INT) error("'%s' expected int".format(bin.op));
    switch (bin.op) {
    case "<": return Value(l.l < r.l); case "<=": return Value(l.l <= r.l);
    case ">": return Value(l.l > r.l); case ">=": return Value(l.l >= r.l);
    case "+": return Value(l.l + r.l); case "-":  return Value(l.l -  r.l);
    case "*": return Value(l.l * r.l); case "/":  return Value(l.l /  r.l);
    default: error("unknown operator '%s'".format(bin.op)); assert(0);
    }
  }
}
void main(string[] args) {
  if (args.length < 2) {
    stderr.writefln("usage: %s <input>", args[0]);
    return;
  }
  intp = new Interpreter(new Parser(args[1].readText.tokenize).parse, args[1..$]);
  intp.exec;
  merda_exit([Value(0)]);
}
