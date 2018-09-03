{
module L = Lexing
module B = Buffer

open Parser

let get = L.lexeme
let sprintf = Printf.sprintf

let position lexbuf =
    let p = lexbuf.L.lex_curr_p in
        sprintf "%s:%d:%d" 
        p.L.pos_fname p.L.pos_lnum (p.L.pos_cnum - p.L.pos_bol)

exception Error of string

let error lexbuf fmt = 
    Printf.kprintf (fun msg -> 
        raise (Error ((position lexbuf)^" "^msg))) fmt

}

let ws = [' ' '\t']
let nl = ['\n']
let digit = ['0'-'9']
let alpha = ['a'-'z' 'A'-'Z' '_' '.']
let id    = alpha (alpha|digit)*
let num   = '-'? digit+
let start_proc = ".cfi_startproc"
let directive = ".text" | ".globl" | ".cfi_endproc" | ".size" | ".section" | ".file" | ".ident"
    |  ".p2align" |  ".data" | ".align"
let ignored = ".cfi_def_cfa_offset" | ".cfi_offset" | ".cfi_remember_state" | ".cfi_restore" 

let regs32 = "%eax" | "%ebx" | "%ecx" | "%edx" | "%ebp" | "%esi" | "%edi" | "%esp"
let regs64 = "%rax" | "%rbx" | "%rcx" | "%rdx" | "%rbp" | "%rsi" | "%rdi" | "%rsp"
    | "%r8" | "%r9" | "%r10" | "%r11" | "%r12" | "%r13" 

    (* | "%r14" | "%r15"  <--- we use them, so fail if used by gcc *) 

    | "%rip"      (* <--- translated at parser level to different addressing mode *)

rule read = parse
| ws+       { read lexbuf  }
| ".text"   { DIR(".text") }
| ".type"   { TYPE }
| "@function" { FUNCTION }
| "@object" { OBJECT }
| start_proc { FUN_START }
| directive [^'\n']*  { DIR(get lexbuf) }
| ignored [^'\n']* { IGN(get lexbuf) }
| nl        { L.new_line lexbuf; LINE  }
| '('       { LPAR          }
| ')'       { RPAR          }
| ','       { COMMA         }
| ':'       { COLON         }
| regs64    { REG(get lexbuf) }
| regs32    { REG(get lexbuf) }
| "leaq"    { ALU2(LEA)   }
| "addq"     { ALU2(ADD)   }
| "subq"     { ALU2(SUB)   }
| "andq"     { ALU2(AND)   }
| "orq"      { ALU2(OR)    }
| "xorq"     { ALU2(XOR)   }
| "xorl"     { ALU2(XOR)   }
| "testq"     { ALU2(TEST)   }
| "cmpq"     { ALU2(CMP)   }
| "movl"    { MOVE(MOV) }
| "movq"    { MOVE(MOV) }
| "rep ret" { CTL0(RET) }
| "ret"     { CTL0(RET) }
| "jne"     { CTL1(Jcc(NE)) }
| "je"      { CTL1(Jcc(E))  }
| "jle"     { CTL1(Jcc(LE)) }
| "jl"      { CTL1(Jcc(L))  }
| "jge"     { CTL1(Jcc(GE)) }
| "jg"     { CTL1(Jcc(G)) }
| "jmp"     { CTL1(JMP) }
| "call"    { CTL1(CALL) }
| "pushq"    { PUPO(PUSH) }
| "popq"     { PUPO(POP) }
| "imulq"   { ALU2(MUL) }
| ".quad"   { QUAD }
| num       { NUM(get lexbuf) }
| '$' num   { NUM(get lexbuf) }
| id        { ID(get lexbuf)}
| eof       { EOF           }
| _         { raise (Error (Printf.sprintf "unhandled '%s' - in: " (get lexbuf))) }

