  type condition =  E | NE | G | GE | L | LE | A | AE | B | BE

  type opcode = ADD | SUB | AND | OR | XOR | CMP | LEA | TEST | MOV | RET | JMP | SAR | SAL | SHR 
                | Jcc of condition | CBcc of condition | CMOVcc of condition
                | CALL | PUSH | POP | MUL | IMUL | SYSCALL | MOVABSQ

(*
  Eaxxx explanation: names are given according to how the Ea is computed
  D displacement (32 bit immediate)
  Z register, possibly shifted by a shift amount
  S base register
  Each may be present or not (though at least one of them must be present)
 *)


  type imm = 
  | Value of int64 | Expr of string

  type op_spec =
  | Reg of int
  | Imm of imm
  | EaS of int
  | EaZ of int * int
  | EaZS of int * int * int
  | EaD of imm
  | EaDS of imm * int
  | EaDZ of imm * int * int
  | EaDZS of imm * int * int * int

  type line =
  | Label of string
  | Alu2 of opcode * op_spec * op_spec
  | PuPo of opcode * op_spec
  | Move2 of opcode * op_spec * op_spec
  | Ctl3 of opcode * op_spec * op_spec * op_spec
  | Ctl2 of opcode * op_spec * op_spec
  | Ctl1 of opcode * op_spec
  | Ctl0 of opcode
  | Quad of imm
  | Comm of imm * int * int
  | Align of int
  | Directive of string
  | Ignored of string
  | Function of string
  | Object of string
  | Fun_start
  | Fun_end
  | Other of string

let rev_cond cond =
  match cond with
  | E -> E
  | NE -> NE
  | G -> L
  | GE -> LE
  | L -> G
  | LE -> GE
  | A -> B
  | AE -> BE
  | B -> A
  | BE -> AE

let reg_a = 16
let reg_d = 17

