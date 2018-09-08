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
    Bytes.set result (sz - 2 - !i) s.[!i];
    Bytes.set result (sz - 1 - !i) s.[!i + 1];
    i := 2 + !i
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

let asm_imm64 i = (* FIXME: Will not work correctly for full 64 bit values *)
  try
    let ii = 
      if i.[0] = '$' then int_of_string (String.sub i 1 ((String.length i) - 1)) 
      else int_of_string i 
    in
    if ii < 0 then reverse_string (Printf.sprintf "%016x" (ii))
    else reverse_string (Printf.sprintf "%016x" ii)
  with Failure _ -> "????????????????"

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
  | "1" -> "0"
  | "2" -> "1"
  | "4" -> "2"
  | "8" -> "3"
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
        (* operations without or with implicit registers: 1 byte encoding: *)
      | Ctl1(RET,_) ->                             gen ["0"; "0"]

        (* alu/move reg/reg operations, 2 byte encoding: *)
      | Alu2(ADD,Reg(rs),Reg(rd)) ->               gen ["1"; "0"; asm_reg rd; asm_reg rs]
      | Alu2(SUB,Reg(rs),Reg(rd)) ->               gen ["1"; "1"; asm_reg rd; asm_reg rs] 
      | Alu2(AND,Reg(rs),Reg(rd)) ->               gen ["1"; "2"; asm_reg rd; asm_reg rs]
      | Alu2(OR,Reg(rs),Reg(rd)) ->                gen ["1"; "3"; asm_reg rd; asm_reg rs]
      | Alu2(XOR,Reg(rs),Reg(rd)) ->               gen ["1"; "4"; asm_reg rd; asm_reg rs]
      | Alu2(MUL,Reg(rs),Reg(rd)) ->               gen ["1"; "5"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Reg(rs),Reg(rd)) ->              gen ["2"; "0"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Ea1(rs),Reg(rd)) ->              gen ["2"; "1"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Reg(rd),Ea1(rs)) ->              gen ["2"; "2"; asm_reg rd; asm_reg rs]

        (* Lea without immediates: 2 + 3 byte encoding: *)
      | Alu2(LEA,Ea1(rs),Reg(rd)) ->               gen ["3"; "0"; asm_reg rd; asm_reg rs]
      | Alu2(LEA,Ea2(rs,rz),Reg(rd)) ->            gen ["3"; "1"; asm_reg rd; asm_reg rs; asm_reg rz; "0"]
      | Alu2(LEA,Ea3(rs,rz,sh),Reg(rd)) ->         gen ["3"; "2"; asm_reg rd; asm_reg rs; asm_reg rz; asm_sh sh]

        (* alu/move immediate/reg operations: 6 byte encoding: *)
      | Alu2(ADD,Imm(i),Reg(rd)) ->                gen ["4"; "0"; asm_reg rd; "0"; asm_imm i]
      | Alu2(SUB,Imm(i),Reg(rd)) ->                gen ["4"; "1"; asm_reg rd; "0"; asm_imm i]
      | Alu2(AND,Imm(i),Reg(rd)) ->                gen ["4"; "2"; asm_reg rd; "0"; asm_imm i]
      | Alu2(OR,Imm(i),Reg(rd)) ->                 gen ["4"; "3"; asm_reg rd; "0"; asm_imm i]
      | Alu2(XOR,Imm(i),Reg(rd)) ->                gen ["4"; "4"; asm_reg rd; "0"; asm_imm i]
      | Alu2(MUL,Imm(i),Reg(rd)) ->                gen ["4"; "5"; asm_reg rd; "0"; asm_imm i]
      | Move2(MOV,Imm(i),Reg(rd)) ->               gen ["5"; "0"; asm_reg rd; "0"; asm_imm i]
      | Move2(MOV,Ea1b(i,rs),Reg(rd)) ->           gen ["5"; "1"; asm_reg rd; asm_reg rs; asm_imm i]
      | Move2(MOV,Reg(rd),Ea1b(i,rs)) ->           gen ["5"; "2"; asm_reg rd; asm_reg rs; asm_imm i]

        (* Branch/Jmp/Call: 5 + 6 byte encoding: *)
      | Ctl3(CBcc(cond),Reg(rs),Reg(rd),Mem(m)) -> gen ["6"; asm_cond cond; asm_reg rd; asm_reg rs; asm_mem env m]
      | Ctl2(CALL,Mem(d),_) ->                     gen ["6"; "E"; asm_mem env d]
      | Ctl1(JMP,Mem(d)) ->                        gen ["6"; "F"; asm_mem env d]

        (* Lea with immediate: 6 + 7 byte encoding *)
      | Alu2(LEA,Mem(m),Reg(rd)) ->                gen ["7"; "0"; asm_reg rd; "0"; asm_mem env m]
      | Alu2(LEA,Ea1b(i,rs),Reg(rd)) ->            gen ["7"; "1"; asm_reg rd; asm_reg rs; asm_imm i]
      | Alu2(LEA,Ea2b(i,rs,rz),Reg(rd)) ->         gen ["7"; "2"; asm_reg rd; asm_reg rs; asm_reg rz; "0"; asm_imm i]
      | Alu2(LEA,Ea3b(i,rs,rz,sh),Reg(rd)) ->      gen ["7"; "3"; asm_reg rd; asm_reg rs; asm_reg rz; asm_sh sh; asm_imm i]

        (* Compare and branch with immediate and target: 10 byte encoding: *)
      | Ctl3(CBcc(cond),Imm(i),Reg(rd),Mem(m)) ->  gen ["8"; "0"; asm_reg rd; asm_cond cond; asm_imm i; asm_mem env m]

      | Quad(q) -> gen [asm_imm64 q]
      | Label(lab) -> gen [""]
      | something -> Source(something)
    end
   | Error(s1,s2) -> raise (Error_during_assembly (String.concat " " [s1; s2]))

let should_translate line =
  let open Ast in
  match line with
  | Ok(Alu2(_)) | Ok(Move2(_)) | Ok(Ctl1(_)) | Ok(Ctl2(_))
    | Ok(Ctl0(_)) | Ok(Ctl3(_)) | Ok(Label(_)) | Ok(Quad(_)) -> true
  | _ -> false

let print_assembly_line line =
  match line with
  | Assembly(a,s,i) -> Printf.printf "%8s : %-20s  #  " a s; (Printer.line_printer (Ok i))
  | Source(i) -> Printf.printf "<**>                #  "; (Printer.line_printer (Ok i))

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

let prepare lines = List.filter should_translate lines

let first_pass lines =
  let first_pass = List.map (assemble_line []) lines in
  let located = assign_addresses 0 first_pass in
  let env = gather_env [] located in
  env

let second_pass env lines =
  let second_pass = List.map (assemble_line env) lines in
  assign_addresses 0 second_pass

let get_line_as_hex line =
  match line with
  | Assembly(a,s,_) -> (a,s)
  | _ -> raise (Error_during_assembly "internal")

let get_as_hex lines : (string * string) list =
  List.map get_line_as_hex lines
