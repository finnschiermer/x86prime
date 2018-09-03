%{
%}
%token COMMA
%token LPAR
%token RPAR
%token <Ast.opcode> ALU2
%token <Ast.opcode> MOVE
%token <Ast.opcode> PUPO
%token <Ast.opcode> CTL1
%token <Ast.opcode> CTL0
%token COLON
%token QUAD
%token TYPE
%token FUNCTION
%token OBJECT
%token FUN_START
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
 | k = ID COLON  { Ast.Label(k) }
 | i = ALU2 v1 = arg COMMA v2 = arg  { Ast.Alu2(i, v1, v2) }
 | i = MOVE v1 = arg COMMA v2 = arg  { Ast.Move2(i, v1, v2) }
 | i = PUPO v1 = arg                 { Ast.PuPo(i, v1) }
 | i = CTL1 v1 = ID                  { Ast.Ctl1(i, Mem(v1)) }
 | i = CTL0                          { Ast.Ctl0(i) }
 | QUAD i = NUM                      { Ast.Quad(i) }
 | s = DIR                           { Ast.Directive(s) }
 | s = IGN                           { Ast.Ignored(s) }
 | TYPE s = ID COMMA FUNCTION        { Ast.Function(s) }
 | TYPE s = ID COMMA OBJECT          { Ast.Object(s) }
 | FUN_START                         { Ast.Fun_start }
;

arg:
 | LPAR s1 = REG COMMA s2 = REG COMMA i = NUM RPAR { Ast.Ea3(s1,s2,i) }
 | s = ID LPAR s1 = REG RPAR { if s1 = "%rip" then Ast.Mem(s) else Ast.Ea1b(s, s1) }
 | s = NUM LPAR s1 = REG RPAR { if s1 = "%rip" then Ast.Mem(s) else Ast.Ea1b(s, s1) }
 | s = ID   { Ast.Mem(s) }
 | i = NUM  { Ast.Imm(i) }
 | s = REG  { Ast.Reg(s) }
;
