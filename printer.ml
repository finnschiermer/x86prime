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
  | MOV -> "mov"
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
  | Imm(s) -> s
  | Mem(s) -> s
  | Ea1(s1) -> Printf.sprintf "(%s)" s1
  | Ea1b(s, s1) -> Printf.sprintf "%s(%s)" s s1
  | Ea2(s1,s2) -> Printf.sprintf "(%s, %s)" s1 s2
  | Ea2b(s, s1, s2) -> Printf.sprintf "%s(%s, %s)" s s1 s2
  | Ea3(s1,s2,s3) -> Printf.sprintf "(%s, %s, %s)" s1 s2 s3
  | Ea3b(s,s1,s2,s3) -> Printf.sprintf "%s(%s, %s, %s)" s s1 s2 s3

let line_printer line =
  let open Ast in
  match line with
  | Ok(insn) -> begin
      match insn with
      | Label(name) -> Printf.printf "%s:\n" name
      | Alu2(opc,a,b) -> Printf.printf "    %s %s, %s\n" (print_opc opc) (print_arg a) (print_arg b)
      | Move2(opc,a,b) -> Printf.printf "    %s %s, %s\n" (print_opc opc) (print_arg a) (print_arg b)
      | PuPo(opc,a) -> Printf.printf "    %s %s\n" (print_opc opc) (print_arg a)
      | Ctl3(opc,a,b,c) -> Printf.printf "    %s %s,%s,%s\n" (print_opc opc) (print_arg a) (print_arg b) (print_arg c)
      | Ctl2(opc,a,b) -> Printf.printf "    %s %s,%s\n" (print_opc opc) (print_arg a) (print_arg b)
      | Ctl1(opc,a) -> Printf.printf "    %s %s\n" (print_opc opc) (print_arg a)
      | Ctl0(opc) -> Printf.printf "    %s\n" (print_opc opc)
      | Quad(d) -> Printf.printf "    .quad %s\n" d
      | Directive(s) -> Printf.printf "\t\tDirective %s\n" s
      | Ignored(s) -> () (* Printf.printf "\t\tIgnored %s\n" s *)
      | Function(s) -> Printf.printf "    .function %s, @function\n" s
      | Object(s) -> Printf.printf "    .function %s, @object\n" s
      | Fun_start -> Printf.printf "    .cfi_start_proc\n"
      | Other(s) -> Printf.printf "Other %s\n" s
    end
  | Error(a,b) -> Printf.printf "ERROR: %s : %s\n" a b

