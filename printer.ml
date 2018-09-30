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
  | CMP -> "cmpq"
  | LEA -> "leaq"
  | TEST -> "testq"
  | MOV -> "movq"
  | RET -> "ret"
  | Jcc(cc) -> Printf.sprintf "j%s" (print_cond cc)
  | CBcc(cc) -> Printf.sprintf "cb%s" (print_cond cc)
  | JMP -> "jmp"
  | PUSH -> "push"
  | POP -> "pop"
  | CALL -> "call"
  | MUL -> "imulq"
;;

let print_arg arg =
  let open Ast in 
  match arg with
  | Reg(s) -> s
  | Imm(s) -> Printf.sprintf "$%s" s
  | EaS(s1) -> Printf.sprintf "(%s)" s1
  | EaZ(s1,s2) -> Printf.sprintf "(,%s,%s)" s1 s2
  | EaZS(s1,s2,s3) -> Printf.sprintf "(%s, %s, %s)" s1 s2 s3
  | EaD(s) -> Printf.sprintf "%s" s
  | EaDZ(s1,s2,s3) -> Printf.sprintf "%s(, %s, %s)" s1 s2 s3
  | EaDS(s, s1) -> Printf.sprintf "%s(%s)" s s1
  | EaDZS(s, s1, s2,s3) -> Printf.sprintf "%s(%s, %s, %s)" s s1 s2 s3

let print_insn insn =
  let open Ast in
  match insn with
  | Label(name) -> Printf.sprintf "%s:" name
  | Alu2(opc,a,b) -> Printf.sprintf "    %s %s, %s" (print_opc opc) (print_arg a) (print_arg b)
  | Move2(opc,a,b) -> Printf.sprintf "    %s %s, %s" (print_opc opc) (print_arg a) (print_arg b)
  | PuPo(opc,a) -> Printf.sprintf "    %s %s" (print_opc opc) (print_arg a)
  | Ctl3(opc,a,b,c) -> Printf.sprintf "    %s %s,%s,%s" (print_opc opc) (print_arg a) (print_arg b) (print_arg c)
  | Ctl2(opc,a,b) -> Printf.sprintf "    %s %s,%s" (print_opc opc) (print_arg a) (print_arg b)
  | Ctl1(opc,a) -> Printf.sprintf "    %s %s" (print_opc opc) (print_arg a)
  | Ctl0(opc) -> Printf.sprintf "    %s" (print_opc opc)
  | Quad(d) -> Printf.sprintf "    .quad %s" d
  | Comm(nm,sz,aln) -> Printf.sprintf "    .comm %s,%d,%d" nm sz aln
  | Align(d) -> Printf.sprintf "    .align %s" d
  | Directive(s) -> Printf.sprintf "    %s" s
  | Ignored(s) -> Printf.sprintf "    %s" s
  | Function(s) -> Printf.sprintf "    .type %s, @function" s
  | Object(s) -> Printf.sprintf "    .type %s, @object" s
  | Fun_start -> Printf.sprintf "    .cfi_startproc"
  | Other(s) -> Printf.sprintf "Other %s" s

let line_printer line =
  let open Ast in
  match line with
  | Ok(insn) -> Printf.printf "%s\n" (print_insn insn)
  | Error(a,b) -> Printf.printf "ERROR: %s : %s\n" a b

