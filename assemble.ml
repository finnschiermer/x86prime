(* Assemble our subset of x86 instructions (with extensions) *)

exception Error_during_assembly of string

type assem = Assembly of string * string * Ast.line | Source of Ast.line

let asm_reg rd =
  if rd = "%rax" then "0"
  else if rd = "%rbx" then "1"
  else if rd = "%rcx" then "2"
  else if rd = "%rdx" then "3"
  else if rd = "%rbp" then "4"
  else if rd = "%rsi" then "5"
  else if rd = "%rdi" then "6"
  else if rd = "%rsp" then "7"
  else if rd = "%r8" then "8"
  else if rd = "%r9" then "9"
  else if rd = "%r10" then "A"
  else if rd = "%r11" then "B"
  else if rd = "%r12" then "C"
  else if rd = "%r13" then "D"
  else if rd = "%r14" then "E"
  else if rd = "%r15" then "F"
  else if rd = "%eax" then "0" (* same as %rax *) (* Fixme: there are diffs wrt sign extension, which we ignore *)
  else if rd = "%ebx" then "1" (* same as %rax *)
  else if rd = "%ecx" then "2" (* same as %rdx *)
  else if rd = "%edx" then "3" (* same as %rdx *)
  else raise (Error_during_assembly ("Unknown register " ^ rd))

let reverse_string s =
  let sz = String.length s in
  let result = Bytes.create sz in
  let i = ref 0 in
  while !i < sz do
    Bytes.set result (sz - 1 - !i) s.[!i];
    i := 1 + !i
  done;
  Bytes.to_string result

let asm_imm i = 
  try
    let ii = 
      if i.[0] = '$' then int_of_string (String.sub i 1 ((String.length i) - 1)) 
      else int_of_string i 
    in
    if ii < 0 then reverse_string (Printf.sprintf "%08x" (0x100000000 + ii))
    else reverse_string (Printf.sprintf "%08x" ii)
  with Failure _ -> "????????"

let asm_cond c =
  let open Ast in
  match c with
  | E -> "0"
  | NE -> "1"
  | L -> "4"
  | LE -> "5"
  | G -> "6"
  | GE -> "7"
  | A -> "8"
  | AE -> "9"
  | B -> "A"
  | BE -> "B"

let asm_sh sh =
  match sh with
  | "1" -> "8"
  | "2" -> "9"
  | "4" -> "A"
  | "8" -> "B"
  | _ -> "?"

let asm_mem env m =
  match List.assoc_opt m env with
  | Some v -> reverse_string v
  | None -> "????????"

let assemble_line env line : assem =
  let open Ast in
  match line with
  | Ok(insn) -> begin
      let gen l : assem = Assembly ("?", (String.concat "" l), insn) in
      match insn with
        (* 1 byte insn: *)
      | Ctl1(RET,_) ->                             gen ["0"; "0"]

        (* 2 byte insn: *)
      | Alu2(ADD,Reg(rs),Reg(rd)) ->               gen ["1"; "0"; asm_reg rd; asm_reg rs]
      | Alu2(SUB,Reg(rs),Reg(rd)) ->               gen ["1"; "1"; asm_reg rd; asm_reg rs] 
      | Alu2(AND,Reg(rs),Reg(rd)) ->               gen ["1"; "2"; asm_reg rd; asm_reg rs]
      | Alu2(OR,Reg(rs),Reg(rd)) ->                gen ["1"; "3"; asm_reg rd; asm_reg rs]
      | Alu2(XOR,Reg(rs),Reg(rd)) ->               gen ["1"; "4"; asm_reg rd; asm_reg rs]
      | Alu2(MUL,Reg(rs),Reg(rd)) ->               gen ["1"; "5"; asm_reg rd; asm_reg rs]
      | Alu2(LEA,Ea1(rs),Reg(rd)) ->               gen ["1"; "6"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Reg(rs),Reg(rd)) ->              gen ["1"; "7"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Ea1(rs),Reg(rd)) ->              gen ["1"; "8"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Reg(rd),Ea1(rs)) ->              gen ["1"; "9"; asm_reg rd; asm_reg rs]

        (* 3 byte insn: *)
      | Alu2(LEA,Ea2(rs,rz),Reg(rd)) ->            gen ["2"; "8"; asm_reg rd; asm_reg rs; asm_reg rz; "0"]
      | Alu2(LEA,Ea3(rs,rz,sh),Reg(rd)) ->         gen ["2"; asm_sh sh; asm_reg rd; asm_reg rs; asm_reg rz; "0"]

        (* 5 byte insn: *)
      | Alu2(ADD,Imm(i),Reg(rd)) ->                gen ["3"; asm_reg rd; asm_imm i]
      | Alu2(SUB,Imm(i),Reg(rd)) ->                gen ["4"; asm_reg rd; asm_imm i]
      | Alu2(AND,Imm(i),Reg(rd)) ->                gen ["5"; asm_reg rd; asm_imm i]
      | Alu2(OR,Imm(i),Reg(rd)) ->                 gen ["6"; asm_reg rd; asm_imm i]
      | Alu2(XOR,Imm(i),Reg(rd)) ->                gen ["7"; asm_reg rd; asm_imm i]
      | Alu2(MUL,Imm(i),Reg(rd)) ->                gen ["8"; asm_reg rd; asm_imm i]
      | Ctl2(CALL,Mem(d),_) ->                     gen ["9"; "0"; asm_mem env d]
      | Ctl1(JMP,Mem(d)) ->                        gen ["9"; "1"; asm_mem env d]
      | Move2(MOV,Imm(i),Reg(rd)) ->               gen ["A"; asm_reg rd; asm_imm i]

        (* 6 byte insn: *)
      | Alu2(LEA,Mem(m),Reg(rd)) ->                gen ["B"; "0"; asm_reg rd; "0"; asm_mem env m]
      | Alu2(LEA,Ea1b(i,rs),Reg(rd)) ->            gen ["C"; "0"; asm_reg rd; asm_reg rs; asm_imm i]
      | Alu2(LEA,Ea2b(i,rs,rz),Reg(rd)) ->         gen ["C"; "8"; asm_reg rd; asm_reg rs; asm_reg rz; "0"; asm_imm i]
      | Alu2(LEA,Ea3b(i,rs,rz,sh),Reg(rd)) ->      gen ["C"; asm_sh sh; asm_reg rd; asm_reg rs; asm_reg rz; "0"; asm_imm i]
      | Ctl3(CBcc(cond),Reg(rs),Reg(rd),Mem(m)) -> gen ["D"; asm_cond cond; asm_reg rd; asm_reg rs; asm_mem env m]
      | Move2(MOV,Ea1b(i,rs),Reg(rd)) ->           gen ["E"; "0"; asm_reg rd; asm_reg rs; asm_imm i]
      | Move2(MOV,Reg(rd),Ea1b(i,rs)) ->           gen ["E"; "1"; asm_reg rd; asm_reg rs; asm_imm i]

        (* 10 byte insn: *)
      | Ctl3(CBcc(cond),Imm(i),Reg(rd),Mem(m)) ->  gen ["F"; asm_cond cond; asm_reg rd; "0"; asm_imm i; asm_mem env m]


      | Label(lab) -> gen [""]
      | something -> Source(something)
    end
  | Error(s1,s2) -> raise (Error_during_assembly (String.concat " " [s1; s2]))

let print_assembly_line line =
  match line with
  | Assembly(a,s,i) -> Printf.printf "%8s : %-20s  #  " a s; (Printer.line_printer (Ok i))
  | Source(i) -> Printf.printf "<**>                #  "; (Printer.line_printer (Ok i))

let should_translate line =
  let open Ast in
  match line with
  | Ok(Alu2(_)) | Ok(Move2(_)) | Ok(Ctl1(_)) | Ok(Ctl2(_))
    | Ok(Ctl0(_)) | Ok(Ctl3(_)) | Ok(Label(_)) -> true
  | _ -> false

let print_assembly lines =
  List.iter print_assembly_line lines

let rec assign_addresses curr_add lines =
  match lines with
  | Assembly(_,encoding,insn) :: rest -> 
     Assembly(Printf.sprintf "%08x" curr_add, encoding, insn) :: assign_addresses (curr_add + (String.length encoding) / 2) rest
  | s :: rest -> s :: assign_addresses curr_add rest
  | [] -> []

let rec gather_env env lines =
  match lines with
  | Assembly(addr, encoding, Ast.Label(lab)) :: rest -> gather_env ((lab, addr) :: env) rest
  | s :: rest -> gather_env env rest
  | [] -> env

let rec print_env env =
  match env with
  | (a,b) :: tail -> Printf.printf "%s -> %s\n" a b; print_env tail
  | [] -> ()

let assemble_lines lines =
  let lines = List.filter should_translate lines in
  let first_pass = List.map (assemble_line []) lines in
  let located = assign_addresses 0 first_pass in
  let env = gather_env [] located in
  let second_pass = List.map (assemble_line env) lines in
  print_assembly (assign_addresses 0 second_pass)

