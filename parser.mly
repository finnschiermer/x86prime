%{
exception IllegalShiftAmount of int

let encode_sh i =
  match (Int64.to_int i) with
  | 1 -> 0
  | 2 -> 1
  | 4 -> 2
  | 8 -> 3
  | v -> raise (IllegalShiftAmount v)

%}
%token COMMA
%token LPAR
%token RPAR
%token SAR
%token SAL
%token SHR
%token INC
%token DEC
%token <Ast.opcode> ALU2
%token <Ast.opcode> MOVE
%token <Ast.opcode> PUPO
%token <Ast.opcode> CTL0
%token <Ast.opcode> CTL1
%token <Ast.opcode> CTL2
%token <Ast.opcode> CTL3
%token COLON
%token QUAD
%token COMM
%token ALIGN
%token TYPE
%token FUNCTION
%token ENDFUNCTION
%token OBJECT
%token FUN_START
%token DOLLAR
%token <string> DIR
%token <string> IGN
%token <string> ID
%token <int> REG
%token <int64> NUM
%token LINE
%token EOF

%start <Ast.line> aline
%%
aline:
 | i = instruction EOF { i }
 | i = instruction IGN EOF { i }

instruction:
 | k = ID COLON                      { Ast.Label(k) }
 | SAR v1 = arg                      { Ast.Alu2(Ast.SAR, Imm(Value(Int64.one)), v1) }
 | SAR v1 = arg COMMA v2 = arg       { Ast.Alu2(Ast.SAR, v1, v2) }
 | SHR v1 = arg                      { Ast.Alu2(Ast.SHR, Imm(Value(Int64.one)), v1) }
 | SHR v1 = arg COMMA v2 = arg       { Ast.Alu2(Ast.SHR, v1, v2) }
 | SAL v1 = arg                      { Ast.Alu2(Ast.SAL, Imm(Value(Int64.one)), v1) }
 | SAL v1 = arg COMMA v2 = arg       { Ast.Alu2(Ast.SAL, v1, v2) }
 | INC v1 = arg                      { Ast.Alu2(Ast.ADD, Imm(Value(Int64.one)), v1) }
 | DEC v1 = arg                      { Ast.Alu2(Ast.SUB, Imm(Value(Int64.one)), v1) }
 | i = ALU2 v1 = arg COMMA v2 = arg  { Ast.Alu2(i, v1, v2) }
 | i = MOVE v1 = arg COMMA v2 = arg  { Ast.Move2(i, v1, v2) }
 | i = PUPO v1 = arg                 { Ast.PuPo(i, v1) }
 | i = CTL3 DOLLAR v1 = NUM COMMA v2 = REG COMMA t = ID  { Ast.Ctl3(i, Ast.Imm(Value(v1)), Ast.Reg(v2), Ast.EaD(Expr(t))) }
 | i = CTL3 v1 = REG COMMA v2 = REG COMMA t = ID  { Ast.Ctl3(i, Ast.Reg(v1), Ast.Reg(v2), Ast.EaD(Expr(t))) }
 | i = CTL1 v1 = ID                  { Ast.Ctl1(i, EaD(Expr(v1))) }
 | i = CTL1 ri = REG                 { Ast.Ctl1(i, Reg(ri)) }
 | i = CTL2 im = ID COMMA ri = REG   { Ast.Ctl2(i, EaD(Expr(im)), Reg(ri)) }
 | i = CTL0                          { Ast.Ctl0(i) }
 | QUAD i = NUM                      { Ast.Quad(Value(i)) }
 | COMM s = ID COMMA sz = NUM COMMA aln = NUM  { Ast.Comm(Expr(s), Int64.to_int sz, Int64.to_int aln) }
 | ALIGN i = NUM                     { Ast.Align(Int64.to_int i) }
 | s = DIR                           { Ast.Directive(s) }
 | s = IGN                           { Ast.Ignored(s) }
 | TYPE s = ID COMMA FUNCTION        { Ast.Function(s) }
 | TYPE s = ID COMMA OBJECT          { Ast.Object(s) }
 | ENDFUNCTION                       { Ast.Fun_end }
 | FUN_START                         { Ast.Fun_start }
 | LINE                              { Ast.Ignored("") }
 | EOF                               { Ast.Ignored("") }
;

arg:
 | LPAR s1 = REG RPAR { Ast.EaS(s1) }
 | LPAR s1 = REG COMMA s2 = REG RPAR { Ast.EaZS(s1,s2,1) }
 | LPAR COMMA s2 = REG RPAR { Ast.EaZ(s2,1) }
 | LPAR s1 = REG COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaZS(s1,s2, encode_sh i) }
 | LPAR COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaZ(s2, encode_sh i) }
 | s = ID LPAR s1 = REG RPAR { if s1 = -1 then Ast.EaD(Ast.Expr(s)) else Ast.EaDS(Ast.Expr(s), s1) }
 | s = NUM LPAR s1 = REG RPAR { if s1 = -1 then Ast.EaD(Ast.Value(s)) else Ast.EaDS(Ast.Value(s), s1) }
 | s = ID LPAR s1 = REG COMMA s2 = REG RPAR { Ast.EaDZS(Ast.Expr(s),s1,s2, 0) }
 | s = ID LPAR s1 = REG COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZS(Ast.Expr(s),s1,s2, encode_sh i) }
 | s = NUM LPAR s1 = REG COMMA s2 = REG RPAR { Ast.EaDZS(Ast.Value(s),s1,s2,0) }
 | s = NUM LPAR s1 = REG COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZS(Ast.Value(s),s1,s2, encode_sh i) }
 | s = ID LPAR COMMA s2 = REG RPAR { Ast.EaDZ(Expr(s),s2, 0) }
 | s = ID LPAR COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZ(Expr(s),s2,encode_sh i) }
 | s = NUM LPAR COMMA s2 = REG RPAR { Ast.EaDZ(Ast.Value(s),s2,0) }
 | s = NUM LPAR COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZ(Ast.Value(s),s2,encode_sh i) }
 | DOLLAR s = ID   { Ast.Imm(Ast.Expr(s)) }
 | DOLLAR i = NUM  { Ast.Imm(Ast.Value(i)) }
 | s = ID   { Ast.EaD(Ast.Expr(s)) }
 | i = NUM  { Ast.EaD(Ast.Value(i)) }
 | s = REG  { Ast.Reg(s) }
;
