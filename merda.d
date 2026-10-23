import std, core.sys.posix.dlfcn, core.stdc.stdlib : exit;
enum : ulong { NONE, RETURN, BREAK, CONTINUE }
enum : ubyte { T_NIL, T_INT, T_STR, T_ARR, T_MAP }
struct Value {
  ubyte t; union { long l; string s; Value[] a; Value[string] m; }
  this(ubyte t_) { t=t_; }
  this(long l_) { t=T_INT,l=l_; }
  this(bool b_) { this(b_.to!long); }
  this(string s_) { t=T_STR,s=s_; }
  this(Value[] a_) { t=T_ARR,a=a_; }
  this(Value[string] m_) { t=T_MAP,m=m_; }
  bool isTrue() => t==T_INT? l!=0 : t==T_STR? s.length!=0 : t==T_ARR? a.length!=0 : t==T_MAP? m.length!=0 : false;
  bool opEquals(Value o) => t==o.t? (t==T_INT? l==o.l : t==T_STR? s==o.s : t==T_ARR? a==o.a : t==T_MAP? m==o.m : true) : false;
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
    } else if (!is_blk && "+-*/!=<>,(){}[].".canFind(chr)) {
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
    foreach (func; i.funs.byKeyValue) gintp.funs[func.key] = func.value;
    foreach (glob; i.funs["<GLOBAL>"].vars.byKeyValue) gintp.funs["<GLOBAL>"].vars[glob.key] = glob.value;
  }
  return Value(T_NIL);
}
Value merda_map(Value[] args) {
  if (args.length % 2 != 0) error("map expects (key, value, ...)");
  auto map = new Value[string];
  for (auto i = 0; i < args.length; i += 2)
    if (args[i].t==T_STR) map[args[i].s]=args[i+1]; else error("map key should be string");
  return Value(map);
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
Value function(Value[])[string] extn; void*[] libs; Interpreter gintp; Value gargs;
enum NodeType {
  LOAD_CONST, MAKE_FUNC, CALL_FUNC, UNARY, BINARY, WHILE,
  IFELSE, RETURN, BLOCK, VARIABLE, MAKE_ARRAY, ARRAY_INDEX,
}
struct NodeIfCond { Node* cond, expr; }
struct NodeVariable { string name; Node* expr; }
struct NodeMakeFunc { string name; string[] args; Node* expr; }
struct NodeCallFunc { string name; Node*[] args; }
struct NodeBinary { string op; Node* left, right; }
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
    Node* expr = null;
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
    auto idx = NodeArrayIndex(array: arr, expr: null);
    if (toks[cur] == ".") {
      consume("."); /* XXX: maybe check if token is valid identifier */
      idx.index = new Node(NodeType.LOAD_CONST, load_const: Value(toks[cur++]));
    } else {
      consume("[");
      idx.index = genExpr;
      consume("]");
    }
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
      return new Node(NodeType.UNARY, binary: NodeBinary(toks[cur++], genPrimary, null));
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
    while (toks[cur] == "[" || toks[cur] == ".") res = genArrayIndex(res);
    return res;
  }
}
struct Function { string[] args; Value[string] vars; Node* body; }
class Interpreter {
  ulong loop_out; Function[string] funs; Function* cfun; const Value delegate(Node*)[] _exprs;
  this(Node*[] code) {
    cfun = &(funs["<GLOBAL>"] = Function(vars: ["args": gargs], body: new Node(NodeType.BLOCK, block: code)));
    extn = ["extern": &merda_extern, "import": &merda_import, "map": &merda_map, "exit": &merda_exit];
    _exprs = [
      &this.execMakeFunc, &this.execCallFunc, &this.execUnary, &this.execBinary, &this.execWhile, &this.execIfElse,
      &this.execReturn, &this.execBlock, &this.execVariable, &this.execMakeArray, &this.execArrayIndex,
    ];
  }
  Value exec() => execExpr(funs["<GLOBAL>"].body);
  Value execFunc(Function fn, Value[] args = []) {
    auto pfun = cfun; cfun = &fn;
    foreach (i, arg; cfun.args) cfun.vars[arg] = i<args.length? args[i] : Value(T_NIL);
    auto res = execExpr(cfun.body);
    loop_out = NONE, cfun = pfun;
    return res;
  }
  Value execExpr(Node* node) {
    return node.t == NodeType.LOAD_CONST? node.load_const : _exprs[cast(ulong)node.t-1](node);
  }
  Value execMakeFunc(Node* node) {
    funs[node.make_func.name] = Function(node.make_func.args, new Value[string], node.make_func.expr);
    foreach (arg; funs[node.make_func.name].args) funs[node.make_func.name].vars[arg] = Value(T_NIL);
    return Value(T_NIL);
  }
  Value execCallFunc(Node* node) {
    auto args = node.call_func.args.map!(a => execExpr(a)).array;
    if (node.call_func.name in funs) return execFunc(funs[node.call_func.name], args);
    if (node.call_func.name in extn) return extn[node.call_func.name](args);
    error("function '%s' does not exist".format(node.call_func.name)); assert(0);
  }
  Value execVariable(Node* node) {
    auto v=node.variable.name, p="global_", c=v.length>p.length&&v.startsWith(p), n=c?v[p.length..$]:v;
    if (node.variable.expr !is null) {
      auto val = execExpr(node.variable.expr);
      return c? (funs["<GLOBAL>"].vars[n] = val) : (cfun.vars[node.variable.name] = val);
    }
    if (node.variable.name in cfun.vars) return cfun.vars[node.variable.name];
    if (c && n in funs["<GLOBAL>"].vars) return funs["<GLOBAL>"].vars[n];
    error("variable '%s' does not exist".format(node.variable.name)); assert(0);
  }
  Value execMakeArray(Node* node) => Value(node.block.map!(e => execExpr(e)).array);
  Value execArrayIndex(Node* node) {
    auto array = execExpr(node.array_index.array), index = execExpr(node.array_index.index);
    if (array.t == T_MAP) {
      if (index.t != T_STR) error("map key may only be string");
      if (node.array_index.expr !is null) return array.m[index.s] = execExpr(node.array_index.expr);
      if (index.s !in array.m) error("map key does not exist");
      return array.m[index.s];
    }
    if (![T_STR, T_ARR].canFind(array.t)) error("can only index arrays");
    auto len = array.t==T_STR? array.s.length : array.a.length;
    if (index.t!=T_INT || (index.l<0 || index.l>=len)) error("index out of range");
    if (node.array_index.expr !is null) {
      if (array.t != T_ARR) error("cannot assign to string index");
      return array.a[index.l] = execExpr(node.array_index.expr);
    }
    return array.t==T_STR? Value(""~array.s[index.l]) : array.a[index.l];
  }
  Value execReturn(Node* node) {
    loop_out = node.ret.ret_type;
    return (node.ret.expr is null)? Value(T_NIL) : execExpr(node.ret.expr);
  }
  Value execWhile(Node* node) {
    auto res = Value(T_NIL);
    while (execExpr(node.ifelse[0].cond).isTrue) {
      res = execExpr(node.ifelse[0].expr);
      if (loop_out == RETURN) return res;
      else if (loop_out == BREAK) { loop_out = NONE; return res; }
      else if (loop_out == CONTINUE) { loop_out = NONE; continue; }
    }
    return res;
  }
  Value execIfElse(Node* node) {
    foreach (cond; node.ifelse) if (execExpr(cond.cond).isTrue) return execExpr(cond.expr);
    return Value(T_NIL);
  }
  Value execBlock(Node* node) {
    auto res = Value(T_NIL);
    foreach (n; node.block) {
      res = execExpr(n);
      if (loop_out != NONE) break;
    }
    return res;
  }
  Value execUnary(Node* node) {
    auto o = node.binary.op, v = execExpr(node.binary.left);
    if (o == "!") return Value(!v.isTrue); else if (v.t != T_INT) error("'%s' expected int".format(o));
    return o == "-"? Value(-v.l) : Value(+v.l);
  }
  Value execBinary(Node* node) {
    auto o = node.binary.op, l = execExpr(node.binary.left), r = execExpr(node.binary.right);
    /**/ if (o == "==") return Value(l == r); else if (o == "and") return Value(l.isTrue && r.isTrue);
    else if (o == "!=") return Value(l != r); else if (o == "or")  return Value(l.isTrue || r.isTrue);
    else if (l.t != T_INT || r.t != T_INT) error("'%s' expected int".format(o));
    switch (o) {
    case "<": return Value(l.l < r.l); case "<=": return Value(l.l <= r.l);
    case ">": return Value(l.l > r.l); case ">=": return Value(l.l >= r.l);
    case "+": return Value(l.l + r.l); case "-":  return Value(l.l -  r.l);
    case "*": return Value(l.l * r.l); case "/":  return Value(l.l /  r.l);
    default: error("unknown operator '%s'".format(o)); assert(0);
    }
  }
}
void main(string[] args) {
  if (args.length < 2) {
    stderr.writefln("usage: %s <input>", args[0]);
    return;
  }
  if (!args[1].exists || args[1].isDir) error("could not read file '%s'".format(args[1]));
  gargs = Value(args[1..$].map!(a => Value(a)).array);
  (gintp = new Interpreter(new Parser(args[1].readText.tokenize).parse)).exec;
  merda_exit([Value(0)]);
}
