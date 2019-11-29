let print_cond cc =
  let open Ast in
  match cc with
  | E -> "e"
  | NE -> "ne"
  | G -> "g"
  | GE -> "ge"
  | L -> "l"
  | LE -> "le"
  | A -> "a"
  | AE -> "ae"
  | B -> "b"
  | BE -> "be"

let print_opc opc =
  let open Ast in
  match opc with
  | ADD -> "addq"
  | SUB -> "subq"
  | AND -> "andq"
  | OR -> "orq"
  | XOR -> "xorq"
  | SAR -> "sarq"
  | SAL -> "salq"
  | SHR -> "shrq"
  | CMP -> "cmpq"
  | LEA -> "leaq"
  | TEST -> "testq"
  | MOV -> "movq"
  | RET -> "ret"
  | Jcc(cc) -> Printf.sprintf "j%s" (print_cond cc)
  | CBcc(cc) -> Printf.sprintf "cb%s" (print_cond cc)
  | CMOVcc(cc) -> Printf.sprintf "cmov%s" (print_cond cc)
  | JMP -> "jmp"
  | PUSH -> "push"
  | POP -> "pop"
  | CALL -> "call"
  | MUL -> "mulq"
  | IMUL -> "imulq"
  | SYSCALL -> "syscall"
  | MOVABSQ -> "movabsq"
;;

let reg_name reg =
  match reg with
  | 0 -> "%rax"
  | 1 -> "%rbx"
  | 2 -> "%rcx"
  | 3 -> "%rdx"
  | 4 -> "%rbp"
  | 5 -> "%rsi"
  | 6 -> "%rdi"
  | 7 -> "%rsp"
  | 8 -> "%r8"
  | 9 -> "%r9"
  | _ -> Printf.sprintf "%%r%-2d" reg


let print_imm (imm : Ast.imm) =
  let open Ast in
  match imm with
  | Value(v) -> begin
      let i = Int64.to_int v in
      if i < 0 then Printf.sprintf "-0x%X" (- i)
      else Printf.sprintf "0x%X" i
    end
  | Expr(e) -> e

let print_sh sh =
  match sh with
  | 0 -> "1"
  | 1 -> "2"
  | 2 -> "4"
  | 3 -> "8"
  | _ -> "?"

let print_arg arg =
  let open Ast in 
  match arg with
  | Reg(s) -> reg_name s
  | Imm(s) -> Printf.sprintf "$%s" (print_imm s)
  | EaS(s1) -> Printf.sprintf "(%s)" (reg_name s1)
  | EaZ(s1,s2) -> Printf.sprintf "(,%s,%s)" (reg_name s1) (print_sh s2)
  | EaZS(s1,s2,s3) -> Printf.sprintf "(%s, %s, %s)" (reg_name s1) (reg_name s2) (print_sh s3)
  | EaD(s) -> Printf.sprintf "%s" (print_imm s)
  | EaDZ(s1,s2,s3) -> Printf.sprintf "%s(, %s, %s)" (print_imm s1) (reg_name s2) (print_sh s3)
  | EaDS(s, s1) -> Printf.sprintf "%s(%s)" (print_imm s) (reg_name s1)
  | EaDZS(s, s1, s2,s3) -> Printf.sprintf "%s(%s, %s, %s)" (print_imm s) (reg_name s1) (reg_name s2) (print_sh s3)

let print_insn insn =
  let open Ast in
  match insn with
  | Label(name) -> Printf.sprintf "%s:" name
  | Alu2(opc,a,b)
  | Move2(opc,a,b) ->  Printf.sprintf "    %s %s, %s" (print_opc opc) (print_arg a) (print_arg b)
  | PuPo(opc,a) -> Printf.sprintf "    %s %s" (print_opc opc) (print_arg a)
  | Ctl3(opc,a,b,c) -> Printf.sprintf "    %s %s, %s, %s" (print_opc opc) (print_arg a) (print_arg b) (print_arg c)
  | Ctl2(opc,a,b) -> Printf.sprintf "    %s %s, %s" (print_opc opc) (print_arg a) (print_arg b)
  | Ctl1(opc,a) -> Printf.sprintf "    %s %s" (print_opc opc) (print_arg a)
  | Ctl0(opc) -> Printf.sprintf "    %s" (print_opc opc)
  | Quad(i) -> Printf.sprintf "    .quad %s" (print_imm i)
  | Comm(i,sz,aln) -> Printf.sprintf "    .comm %s,%d,%d" (print_imm i) sz aln
  | Align(d) -> Printf.sprintf "    .align %d" d
  | Directive(s) -> Printf.sprintf "    %s" s
  | Ignored(s) -> Printf.sprintf "    %s" s
  | Function(s) -> Printf.sprintf "    .type %s, @function" s
  | Object(s) -> Printf.sprintf "    .type %s, @object" s
  | Fun_start -> Printf.sprintf "    .cfi_startproc"
  | Fun_end -> Printf.sprintf "    .cfi_endproc"
  | Other(s) -> Printf.sprintf "Other %s" s

let line_printer oc line =
  let open Ast in
  match line with
  | Ok(insn) -> Printf.fprintf oc "%s\n" (print_insn insn)
  | Error(a,b) -> Printf.fprintf oc "ERROR: %s : %s\n" a b

