%{
%}
%token COMMA
%token LPAR
%token RPAR
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
%token OBJECT
%token FUN_START
%token DOLLAR
%token <string> DIR
%token <string> IGN
%token <string> ID
%token <string> REG
%token <string> NUM
%token LINE
%token EOF

%start <Ast.line> aline
%%
aline:
 | k = ID COLON                      { Ast.Label(k) }
 | i = ALU2 v1 = arg COMMA v2 = arg  { Ast.Alu2(i, v1, v2) }
 | i = MOVE v1 = arg COMMA v2 = arg  { Ast.Move2(i, v1, v2) }
 | i = PUPO v1 = arg                 { Ast.PuPo(i, v1) }
 | i = CTL3 DOLLAR v1 = NUM COMMA v2 = REG COMMA t = ID  { Ast.Ctl3(i, Ast.Imm(v1), Ast.Reg(v2), Ast.EaD(t)) }
 | i = CTL3 v1 = REG COMMA v2 = REG COMMA t = ID  { Ast.Ctl3(i, Ast.Reg(v1), Ast.Reg(v2), Ast.EaD(t)) }
 | i = CTL1 v1 = ID                  { Ast.Ctl1(i, EaD(v1)) }
 | i = CTL1 ri = REG                 { Ast.Ctl1(i, Reg(ri)) }
 | i = CTL2 im = ID COMMA ri = REG   { Ast.Ctl2(i, EaD(im), Reg(ri)) }
 | i = CTL0                          { Ast.Ctl0(i) }
 | QUAD i = NUM                      { Ast.Quad(i) }
 | COMM s = ID COMMA sz = NUM COMMA aln = NUM  { Ast.Comm(s, int_of_string sz, int_of_string aln) }
 | ALIGN i = NUM                     { Ast.Align(i) }
 | s = DIR                           { Ast.Directive(s) }
 | s = IGN                           { Ast.Ignored(s) }
 | TYPE s = ID COMMA FUNCTION        { Ast.Function(s) }
 | TYPE s = ID COMMA OBJECT          { Ast.Object(s) }
 | FUN_START                         { Ast.Fun_start }
 | LINE                              { Ast.Ignored("") }
 | EOF                               { Ast.Ignored("") }
;

arg:
 | LPAR s1 = REG RPAR { Ast.EaS(s1) }
 | LPAR s1 = REG COMMA s2 = REG RPAR { Ast.EaZS(s1,s2,"1") }
 | LPAR COMMA s2 = REG RPAR { Ast.EaZ(s2,"1") }
 | LPAR s1 = REG COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaZS(s1,s2,i) }
 | LPAR COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaZ(s2,i) }
 | s = ID LPAR s1 = REG RPAR { if s1 = "%rip" then Ast.EaD(s) else Ast.EaDS(s, s1) }
 | s = NUM LPAR s1 = REG RPAR { if s1 = "%rip" then Ast.EaD(s) else Ast.EaDS(s, s1) }
 | s = ID LPAR s1 = REG COMMA s2 = REG RPAR { Ast.EaDZS(s,s1,s2,"1") }
 | s = ID LPAR s1 = REG COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZS(s,s1,s2,i) }
 | s = NUM LPAR s1 = REG COMMA s2 = REG RPAR { Ast.EaDZS(s,s1,s2,"1") }
 | s = NUM LPAR s1 = REG COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZS(s,s1,s2,i) }
 | s = ID LPAR COMMA s2 = REG RPAR { Ast.EaDZ(s,s2,"1") }
 | s = ID LPAR COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZ(s,s2,i) }
 | s = NUM LPAR COMMA s2 = REG RPAR { Ast.EaDZ(s,s2,"1") }
 | s = NUM LPAR COMMA s2 = REG COMMA i = NUM RPAR { Ast.EaDZ(s,s2,i) }
 | DOLLAR s = ID   { Ast.Imm(s) }
 | DOLLAR i = NUM  { Ast.Imm(i) }
 | s = ID   { Ast.EaD(s) }
 | i = NUM  { Ast.EaD(i) }
 | s = REG  { Ast.Reg(s) }
;
