  type condition =  E | NE | G | GE | L | LE | A | AE | B | BE

  type opcode = ADD | SUB | AND | OR | XOR | CMP | LEA | TEST | MOV | RET | JMP 
                | Jcc of condition | CBcc of condition | CALL | PUSH | POP | MUL

(*
  Eaxxx explanation: names are given according to how the Ea is computed
  D displacement (32 bit immediate)
  Z register, possibly shifted by a shift amount
  S base register
  Each may be present or not (though at least one of them must be present)
 *)
  type op_spec =
  | Reg of string
  | Imm of string
(*  | Mem of string *)
  | EaS of string
  | EaZ of string * string
  | EaZS of string * string * string
  | EaD of string
  | EaDS of string * string
  | EaDZ of string * string * string
  | EaDZS of string * string * string * string
(*  | Ea1 of string
  | Ea1b of string * string
  | Ea2 of string * string
  | Ea2b of string * string * string
  | Ea3 of string * string * string
  | Ea3b of string * string * string * string
 *)

  type line =
  | Label of string
  | Alu2 of opcode * op_spec * op_spec
  | PuPo of opcode * op_spec
  | Move2 of opcode * op_spec * op_spec
  | Ctl3 of opcode * op_spec * op_spec * op_spec
  | Ctl2 of opcode * op_spec * op_spec
  | Ctl1 of opcode * op_spec
  | Ctl0 of opcode
  | Quad of string
  | Comm of string * int * int
  | Align of string
  | Directive of string
  | Ignored of string
  | Function of string
  | Object of string
  | Fun_start
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
