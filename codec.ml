(* Decoding from numbers into Ast *)

exception UnimplementedCondition
exception UnknownInstruction
exception UnimplementedScaling

let split_byte byte = (byte lsr 4, byte land 0x0F)

let imm_to_qimm imm =
  if (imm lsr 31) == 0 then
    Int64.of_int imm
  else (* negative *)
    let hi = Int64.shift_left (Int64.of_int 0xFFFFFFFF) 32 in
    let lo = Int64.of_int imm in
    Int64.logor hi lo

let fetch_imm fetch_next =
  let a = fetch_next () in
  let b = fetch_next () in
  let c = fetch_next () in
  let d = fetch_next () in
  let imm = (((((d lsl 8) + c) lsl 8) + b) lsl 8) + a in
  imm_to_qimm imm



let disas_cond cond =
  let open Ast in
  match cond with
  | 0 -> E
  | 1 -> NE
  | 4 -> L
  | 5 -> LE
  | 6 -> G
  | 7 -> GE
  | 8 -> A
  | 9 -> AE
  | 10 -> B
  | 11 -> BE
  | _ -> raise UnimplementedCondition


let decode fetch_next =

  let first_byte = fetch_next () in
  let (hi,lo) = split_byte first_byte in
  let second_byte = fetch_next () in
  let (rd,rs) = split_byte second_byte in
  match hi,lo with
  | 0,0 -> Ast.Ctl1(RET,Reg(rs))
  | 0,1 -> Ast.Ctl0(SYSCALL)
  | 1,0 -> Ast.Alu2(ADD,Reg(rs), Reg(rd))
  | 1,1 -> Ast.Alu2(SUB,Reg(rs), Reg(rd))
  | 1,2 -> Ast.Alu2(AND,Reg(rs), Reg(rd))
  | 1,3 -> Ast.Alu2(OR,Reg(rs), Reg(rd))
  | 1,4 -> Ast.Alu2(XOR,Reg(rs), Reg(rd))
  | 1,5 -> Ast.Alu2(MUL,Reg(rs), Reg(rd))
  | 1,6 -> Ast.Alu2(SAR,Reg(rs), Reg(rd))
  | 1,7 -> Ast.Alu2(SAL,Reg(rs), Reg(rd))
  | 1,8 -> Ast.Alu2(SHR,Reg(rs), Reg(rd))
  | 1,9 -> Ast.Alu2(IMUL,Reg(rs), Reg(rd))
  | 2,1 -> Ast.Move2(MOV,Reg(rs), Reg(rd))
  | 3,1 -> Ast.Move2(MOV,EaS(rs), Reg(rd))
  | 3,9 -> Ast.Move2(MOV,Reg(rd), EaS(rs))
  | 4,_ | 5,_ | 6,_ | 7,_ -> begin (* instructions with 2 bytes + 1 immediate *)
      let imm = fetch_imm fetch_next in
      match hi,lo with
      | 4,0xE -> Ast.Ctl2(CALL,EaD(Value(imm)),Reg(rd))
      | 4,0xF -> Ast.Ctl1(JMP,EaD(Value(imm)))
      | 4,_ -> Ast.Ctl3(CBcc(disas_cond lo),Reg(rs),Reg(rd),EaD(Value(imm)));
      | 5,0 -> Ast.Alu2(ADD,Imm(Value(imm)),Reg(rd))
      | 5,1 -> Ast.Alu2(SUB,Imm(Value(imm)),Reg(rd))
      | 5,2 -> Ast.Alu2(AND,Imm(Value(imm)),Reg(rd))
      | 5,3 -> Ast.Alu2(OR,Imm(Value(imm)),Reg(rd))
      | 5,4 -> Ast.Alu2(XOR,Imm(Value(imm)),Reg(rd))
      | 5,5 -> Ast.Alu2(MUL,Imm(Value(imm)),Reg(rd))
      | 5,6 -> Ast.Alu2(SAR,Imm(Value(imm)),Reg(rd))
      | 5,7 -> Ast.Alu2(SAL,Imm(Value(imm)),Reg(rd))
      | 5,8 -> Ast.Alu2(SHR,Imm(Value(imm)),Reg(rd))
      | 5,9 -> Ast.Alu2(IMUL,Imm(Value(imm)),Reg(rd))
      | 6,4 -> Ast.Move2(MOV,Imm(Value(imm)),Reg(rd))
      | 7,5 -> Ast.Move2(MOV,EaDS(Value(imm),rs),Reg(rd))
      | 7,0xD ->Ast.Move2(MOV,Reg(rd), EaDS(Value(imm),rs))
      | _ -> raise UnknownInstruction
    end
  | 8,_ | 9,_ | 10,_ | 11,_ -> begin (* leaq *)
      let has_third_byte = hi = 9 || hi = 11 in
      let has_imm = hi = 10 || hi = 11 in
      let (rz,sh) = if has_third_byte then split_byte (fetch_next ()) else 0,0 in
      let imm = if has_imm then fetch_imm fetch_next else Int64.zero in
      match lo with
      | 1 -> Ast.Alu2(LEA,EaS(rs),Reg(rd))
      | 2 -> Ast.Alu2(LEA,EaZ(rz, sh),Reg(rd))
      | 3 -> Ast.Alu2(LEA,EaZS(rs,rz, sh),Reg(rd))
      | 4 -> Ast.Alu2(LEA,EaD(Value(imm)),Reg(rd))
      | 5 -> Ast.Alu2(LEA,EaDS(Value(imm), rs),Reg(rd))
      | 6 -> Ast.Alu2(LEA,EaDZ(Value(imm), rz, sh),Reg(rd))
      | 7 -> Ast.Alu2(LEA,EaDZS(Value(imm), rs,rz, sh),Reg(rd))
      | _ -> raise UnknownInstruction
    end
  | 15,_ -> begin (* cbcc with both imm and target *)
      let imm = fetch_imm fetch_next in
      let a_imm = fetch_imm fetch_next in
      Ast.Ctl3(CBcc(disas_cond lo),Imm(Value(imm)),Reg(rd),EaD(Value(a_imm)))
    end
  | _ -> raise UnknownInstruction




(* Encoding from AST into hex format *)

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

let asm_reg rd = Printf.sprintf "%X" rd

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

let asm_mem env (m : Ast.imm) =
  match m with
  | Ast.Value(ii) ->
      if ii < Int64.zero then reverse_string (Printf.sprintf "%08x" (0x100000000 + Int64.to_int ii))
      else reverse_string (Printf.sprintf "%08Lx" ii)
  | Ast.Expr(s) ->
      try (* if it's a numeric literal, use it directly -- if not, try to resolve it from the environment *)
        let ii = int_of_string s in
        if ii < 0 then reverse_string (Printf.sprintf "%08X" (0x100000000 + ii))
        else reverse_string (Printf.sprintf "%08X" ii)
      with Failure _ -> begin
        match List.assoc_opt s env with
        | Some v -> reverse_string v
        | None -> "????????"
      end

let asm_imm env i = asm_mem env i

let asm_mem64 env (m : Ast.imm) =
  match m with
  | Ast.Value(ii) -> reverse_string (Printf.sprintf "%016Lx" (ii))
  | Ast.Expr(s) -> 
      try
        let ii = Int64.of_string s in
        reverse_string (Printf.sprintf "%016Lx" ii)
      with Failure _ -> begin
        match List.assoc_opt s env with
        | Some v -> reverse_string v
        | None -> "????????????????"
      end

let asm_imm64 = asm_mem64


let asm_sh sh =
  match sh with
  | 0 -> "0"
  | 1 -> "1"
  | 2 -> "2"
  | 3 -> "3"
  | _ -> "?"



let assemble insn env =
  let gen l = Some(String.concat "" l) in
  let gen_zeros num = Some(String.make (2 * num) '0') in
  let open Ast in
      match insn with
      | Ctl0(SYSCALL) ->                           gen ["0"; "1"; "0"; "0"]
      | Ctl1(RET,Reg(rs)) ->                       gen ["0"; "0"; "0"; asm_reg rs]

        (* alu/move reg/reg operations, 2 byte encoding: *)
      | Alu2(ADD,Reg(rs),Reg(rd)) ->               gen ["1"; "0"; asm_reg rd; asm_reg rs]
      | Alu2(SUB,Reg(rs),Reg(rd)) ->               gen ["1"; "1"; asm_reg rd; asm_reg rs] 
      | Alu2(AND,Reg(rs),Reg(rd)) ->               gen ["1"; "2"; asm_reg rd; asm_reg rs]
      | Alu2(OR,Reg(rs),Reg(rd)) ->                gen ["1"; "3"; asm_reg rd; asm_reg rs]
      | Alu2(XOR,Reg(rs),Reg(rd)) ->               gen ["1"; "4"; asm_reg rd; asm_reg rs]
      | Alu2(MUL,Reg(rs),Reg(rd)) ->               gen ["1"; "5"; asm_reg rd; asm_reg rs]
      | Alu2(SAR,Reg(rs),Reg(rd)) ->               gen ["1"; "6"; asm_reg rd; asm_reg rs]
      | Alu2(SAL,Reg(rs),Reg(rd)) ->               gen ["1"; "7"; asm_reg rd; asm_reg rs]
      | Alu2(SHR,Reg(rs),Reg(rd)) ->               gen ["1"; "8"; asm_reg rd; asm_reg rs]
      | Alu2(IMUL,Reg(rs),Reg(rd)) ->              gen ["1"; "9"; asm_reg rd; asm_reg rs]
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
      | Alu2(SAR,Imm(i),Reg(rd)) ->                gen ["5"; "6"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(SAL,Imm(i),Reg(rd)) ->                gen ["5"; "7"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(SHR,Imm(i),Reg(rd)) ->                gen ["5"; "8"; asm_reg rd; "0"; asm_imm env i]
      | Alu2(IMUL,Imm(i),Reg(rd)) ->               gen ["5"; "9"; asm_reg rd; "0"; asm_imm env i]
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
      | Alu2(CMOVcc(_),_,_) -> None
      | Quad(q) -> gen [asm_imm64 env q]
      | Comm(nm,sz,aln) -> gen_zeros sz
      | Label(lab) -> gen [""]
      | Align(_) -> gen [""]
      | _ -> None

