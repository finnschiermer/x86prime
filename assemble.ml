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
  else if rd = "%ebx" then "1" (* same as %rbx *)
  else if rd = "%ecx" then "2" (* same as %rcx *)
  else if rd = "%edx" then "3" (* same as %rdx *)
  else if rd = "%ebp" then "4"
  else if rd = "%esi" then "5"
  else if rd = "%edi" then "6"
  else if rd = "%esp" then "7"
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

let asm_imm env i = 
  try
    let ii = int_of_string i in
    if ii < 0 then reverse_string (Printf.sprintf "%08x" (0x100000000 + ii))
    else reverse_string (Printf.sprintf "%08x" ii)
  with Failure _ -> asm_mem env i

let asm_mem64 env m =
  match List.assoc_opt m env with
  | Some v -> reverse_string v
  | None -> "????????????????"

let asm_imm64 env i = 
  try
    let ii = Int64.of_string i in
    if ii < Int64.zero then reverse_string (Printf.sprintf "%016Lx" (ii))
    else reverse_string (Printf.sprintf "%016Lx" ii)
  with Failure _ -> asm_mem64 env i


let assemble_line env line : assem =
  let open Ast in
  match line with
  | Ok(insn) -> begin
      let gen l : assem = Assembly ("?", (String.concat "" l), insn) in
      let gen_zeros num : assem = Assembly("?", (String.make (2 * num) '0'), insn) in
      match insn with
      | Ctl1(RET,Reg(rs)) ->                       gen ["0"; "0"; "0"; asm_reg rs]

        (* alu/move reg/reg operations, 2 byte encoding: *)
      | Alu2(ADD,Reg(rs),Reg(rd)) ->               gen ["1"; "0"; asm_reg rd; asm_reg rs]
      | Alu2(SUB,Reg(rs),Reg(rd)) ->               gen ["1"; "1"; asm_reg rd; asm_reg rs] 
      | Alu2(AND,Reg(rs),Reg(rd)) ->               gen ["1"; "2"; asm_reg rd; asm_reg rs]
      | Alu2(OR,Reg(rs),Reg(rd)) ->                gen ["1"; "3"; asm_reg rd; asm_reg rs]
      | Alu2(XOR,Reg(rs),Reg(rd)) ->               gen ["1"; "4"; asm_reg rd; asm_reg rs]
      | Alu2(MUL,Reg(rs),Reg(rd)) ->               gen ["1"; "5"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Reg(rs),Reg(rd)) ->              gen ["2"; "1"; asm_reg rd; asm_reg rs]
      | Move2(MOV,EaS(rs),Reg(rd)) ->              gen ["3"; "1"; asm_reg rd; asm_reg rs]
      | Move2(MOV,Reg(rd),EaS(rs)) ->              gen ["3"; "9"; asm_reg rd; asm_reg rs]

        (* Branch/Jmp/Call: 6 byte encoding: *)
      | Ctl3(CBcc(cond),Reg(rs),Reg(rd),EaD(m)) -> gen ["4"; asm_cond cond; asm_reg rd; asm_reg rs; asm_mem env m]
      | Ctl2(CALL,EaD(d),Reg(rd)) ->               gen ["4"; "E"; asm_reg rd; "0"; asm_mem env d]
      | Ctl1(JMP,EaD(d)) ->                        gen ["4"; "F"; "0"; "0"; asm_mem env d]

        (* alu/move immediate/reg operations: 6 byte encoding: *)
      | Alu2(ADD,Imm(i),Reg(rd)) ->                gen ["5"; "0"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(SUB,Imm(i),Reg(rd)) ->                gen ["5"; "1"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(AND,Imm(i),Reg(rd)) ->                gen ["5"; "2"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(OR,Imm(i),Reg(rd)) ->                 gen ["5"; "3"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(XOR,Imm(i),Reg(rd)) ->                gen ["5"; "4"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(MUL,Imm(i),Reg(rd)) ->                gen ["5"; "5"; asm_reg rd; "0"; asm_imm env i]
      | Move2(MOV,Imm(i),Reg(rd)) ->               gen ["6"; "4"; asm_reg rd; "0"; asm_imm env i]
      | Move2(MOV,EaDS(i,rs),Reg(rd)) ->           gen ["7"; "5"; asm_reg rd; asm_reg rs; asm_imm env i]
      | Move2(MOV,Reg(rd),EaDS(i,rs)) ->           gen ["7"; "D"; asm_reg rd; asm_reg rs; asm_imm env i]

        (* Lea without immediates: 2 byte encoding: *)
      | Alu2(LEA,EaS(rs),Reg(rd)) ->               gen ["8"; "1"; asm_reg rd; asm_reg rs]

        (* Lea without immediates: 3 byte encoding: *)
      | Alu2(LEA,EaZ(rz,sh),Reg(rd)) ->            gen ["9"; "2"; asm_reg rd; "0"; asm_reg rz; asm_sh sh]
      | Alu2(LEA,EaZS(rs,rz,sh),Reg(rd)) ->        gen ["9"; "3"; asm_reg rd; asm_reg rs; asm_reg rz; asm_sh sh]

        (* Lea with immediate: 6 byte encoding *)
      | Alu2(LEA,EaD(m),Reg(rd)) ->                gen ["A"; "4"; asm_reg rd; "0"; asm_mem env m]
      | Alu2(LEA,EaDS(i,rs),Reg(rd)) ->            gen ["A"; "5"; asm_reg rd; asm_reg rs; asm_imm env i]
        (* Lea with immediate: 7 byte encoding *)
      | Alu2(LEA,EaDZ(i,rz,sh),Reg(rd)) ->         gen ["B"; "6"; asm_reg rd; "0"; asm_reg rz; asm_sh sh; asm_imm env i]
      | Alu2(LEA,EaDZS(i,rs,rz,sh),Reg(rd)) ->     gen ["B"; "7"; asm_reg rd; asm_reg rs; asm_reg rz; asm_sh sh; asm_imm env i]

        (* Compare and branch with immediate and target: 10 byte encoding: *)
      | Ctl3(CBcc(cond),Imm(i),Reg(rd),EaD(m)) ->  gen ["F"; asm_cond cond; asm_reg rd; "0"; asm_imm env i; asm_mem env m]

      | Quad(q) -> gen [asm_imm64 env q]
      | Comm(nm,sz,aln) -> gen_zeros sz
      | Label(lab) -> gen [""]
      | Align(_) -> gen [""]
      | something -> Source(something)
    end
   | Error(s1,s2) -> raise (Error_during_assembly (String.concat " " [s1; s2]))

let should_translate line =
  let open Ast in
  match line with
  | Ok(Alu2(_)) | Ok(Move2(_)) | Ok(Ctl1(_)) | Ok(Ctl2(_))
    | Ok(Ctl0(_)) | Ok(Ctl3(_)) | Ok(Label(_)) | Ok(Quad(_)) | Ok(Comm(_)) | Ok(Align(_)) | Error(_) -> true
  | _ -> false

let print_assembly_line line =
  match line with
  | Assembly(a,s,i) -> Printf.printf "%8s : %-20s  #  " a s; (Printer.line_printer (Ok i))
  | Source(i) -> Printf.printf "<**>                #  "; (Printer.line_printer (Ok i))

let print_assembly lines =
  List.iter print_assembly_line lines

let rec assign_addresses curr_add lines =
  match lines with
  | Assembly(_,encoding,Comm(nm,sz,aln)) :: rest -> begin
        let aligned = (curr_add + (aln - 1)) land (lnot (aln - 1)) in
        Assembly(Printf.sprintf "%08x" aligned, encoding, Comm(nm,sz,aln)) :: assign_addresses (aligned + sz) rest
      end
  | Assembly(_,encoding,Align(q)) :: rest -> begin
      let alignment = int_of_string q in
      let aligned = (curr_add + (alignment - 1)) land (lnot (alignment - 1)) in
      Assembly(Printf.sprintf "%08x" aligned, encoding, Align(q)) :: assign_addresses aligned rest
    end
  | Assembly(_,encoding,Quad(q)) :: rest -> begin
      let alignment = 8 in
      let aligned = (curr_add + (alignment - 1)) land (lnot (alignment - 1)) in
      Assembly(Printf.sprintf "%08x" aligned, encoding, Quad(q)) :: assign_addresses (aligned + 8) rest
    end
  | Assembly(_,encoding,insn) :: rest -> 
     Assembly(Printf.sprintf "%08x" curr_add, encoding, insn) :: assign_addresses (curr_add + (String.length encoding) / 2) rest
  | s :: rest -> s :: assign_addresses curr_add rest
  | [] -> []

let rec gather_env env lines =
  match lines with
  | Assembly(addr, encoding, Ast.Label(lab)) :: rest -> gather_env ((lab, addr) :: env) rest
  | Assembly(addr, encoding, Ast.Comm(nm,sz,aln)) :: rest -> gather_env ((nm, addr) :: env) rest
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
  | Source(i) -> raise (Error_during_assembly (Printf.sprintf "Not a valid x86prime instruction: %s" (Printer.print_insn i)))

let get_as_hex lines : (string * string) list =
  List.map get_line_as_hex lines
