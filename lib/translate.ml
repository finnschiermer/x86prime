let regnr reg =
  match reg with
  | "%r_a" -> 16
  | "%r_d" -> 17
  | "%rax" | "%eax" -> 0
  | "%rbx" | "%ebx" -> 1
  | "%rcx" | "%ecx" -> 2
  | "%rdx" | "%edx" -> 3
  | "%rbp" | "%ebp" -> 4
  | "%rsi" | "%esi" -> 5
  | "%rdi" | "%edi" -> 6
  | "%rsp" | "%esp" -> 7
  | "%r8"  | "%r8d" -> 8
  | "%r9"  | "%r9d" -> 9
  | "%r10" | "%r10d" -> 10
  | "%r11" | "%r11d" -> 11
  | "%r12" | "%r12d" -> 12
  | "%r13" | "%r13d" -> 13
  | "%r14" | "%r14d" -> 14
  | "%r15" | "%r15d" -> 15
  | _ -> 18

let regname nr =
  match nr with
  | 0 -> "%rax"
  | 1 -> "%rbx"
  | 2 -> "%rcx"
  | 3 -> "%rdx"
  | 4 -> "%rbp"
  | 5 -> "%rsi"
  | 6 -> "%rdi"
  | 7 -> "%rsp"
  | 16 -> "%r_a"
  | 17 -> "%r_d"
  | _ -> Printf.sprintf "%%r%-2d" nr

let extract_from_op op =
  let open Ast in
  match op with
  | Reg(r) -> 1 lsl (regnr r)
  | EaS(r) -> 1 lsl (regnr r)
  | EaZ(r,_) -> 1 lsl (regnr r)
  | EaZS(a,b,_) -> (1 lsl (regnr a)) lor (1 lsl (regnr b))
  | EaDS(_,r) -> 1 lsl (regnr r)
  | EaDZ(_,r,_) -> 1 lsl (regnr r)
  | EaDZS(_,a,b,_) -> (1 lsl (regnr a)) lor (1 lsl (regnr b))
  | _ -> 0

let extract_regs line =
  let open Ast in
  match line with
  | (_, insn) -> begin
     match insn with
     | Alu2(_,a,b) -> (extract_from_op a) lor (extract_from_op b)
     | PuPo(_,a) -> extract_from_op a
     | Move2(_,a,b) -> (extract_from_op a) lor (extract_from_op b)
     | Ctl3(_,a,b,c) -> (extract_from_op a) lor (extract_from_op b) lor (extract_from_op c)
     | Ctl2(_,a,b) -> (extract_from_op a) lor (extract_from_op b)
     | Ctl1(_,a) -> extract_from_op a
     | _ -> 0
    end

let caller_saves = 1 lor 4 lor 8 lor 32 lor 64 lor 256 lor 512 lor 1024 lor 2048
let callee_saves = 2 lor 16 lor 4096 lor 8192 lor 16384 lor 32768
let r_a_mask = 1 lsl 16
let r_d_mask = 1 lsl 17

let find_regs func = 
  List.fold_left (lor) 0 (List.map extract_regs func)

let print_regs text reg_list =
  Printf.printf "%s " text;
  let r = ref 0 in
  while !r < 18 do
    if ((1 lsl !r) land reg_list) <> 0 then Printf.printf "%s " (regname !r);
    r := !r + 1;
  done;
  Printf.printf "\n"

let allocate_reg reg_list =
  let result = ref None in
  let r = ref 15 in
  while !r >= 0 && !result = None do
    let mask = 1 lsl !r in
    if (mask land reg_list) <> 0 then result := Some(!r, reg_list land (lnot mask));
    r := !r - 1;
  done;
  !result

let rec txl_instructions lines =
  let open Ast in
  match lines with
  | (lnum, Alu2(MOVABSQ,Imm(a),b)) :: tl -> begin
      let v : Int64.t = Int64.of_string a in
      let lo : Int64.t = Int64.of_int32 (Int64.to_int32 v) in
      let rest = Int64.sub v lo in
      let hi = Int64.shift_right rest 32 in
      (lnum, Alu2(MOV,Imm(Int64.to_string hi), b)) :: (lnum, Alu2(SAL,Imm("32"),b))
         :: (lnum, Alu2(ADD,Imm(Int64.to_string lo), b)) :: txl_instructions tl
    end
  | (_, Ignored(_))::tl | (_, Directive(_))::tl | (_, Function(_))::tl 
    | (_,Object(_))::tl (* | (_, Fun_start) :: tl | (_, Fun_end)::tl *) -> (txl_instructions tl)
  | (lnum, Other(s)) :: tl -> (lnum, Other "    ERROR - no prime for this ---> ") :: (txl_instructions tl)
  | insn :: tl -> insn :: (txl_instructions tl)
  | [] -> []

let translate_body lines =
  let lines = txl_instructions lines in
  let lines = Stack.elim_stack lines in
  Branches.elim_flags (Load_store.convert lines)

exception NotEnoughFreeRegisters

let rec free_up_register lines reg = 
  let open Ast in
  match lines with
  | (lnum, Fun_start) :: tl -> (lnum, Fun_start) :: (lnum, PuPo(PUSH,Reg(reg))) :: free_up_register tl reg
  | (lnum, Ctl0(RET)) :: tl -> (lnum, PuPo(POP,Reg(reg))) :: (lnum, Ctl0(RET)) :: free_up_register tl reg
  | hd :: tl -> hd :: free_up_register tl reg
  | [] -> []

let rebind_register lines from_reg to_reg =
(*  Printf.printf "binding %s to %s\n" from_reg to_reg;*)
  let rebind_reg reg = 
    if reg = from_reg then to_reg else reg
  in
  let rebind_reg_in_op op =
    let open Ast in
    match op with
    | Reg(r) -> Reg(rebind_reg r)
    | EaS(r) -> EaS(rebind_reg r)
    | EaZ(r,v) -> EaZ(rebind_reg r,v)
    | EaZS(a,b,v) -> EaZS(rebind_reg a, rebind_reg b, v)
    | EaDS(d,r) -> EaDS(d,rebind_reg r)
    | EaDZ(d,z,v) -> EaDZ(d,rebind_reg z,v)
    | EaDZS(d,a,b,v) -> EaDZS(d,rebind_reg a, rebind_reg b, v)
    | x -> x
  in
  let rebind_register_in_insn insn =
    let open Ast in
    match insn with
    | (lnum, insn) -> begin
        match(insn) with
        | Alu2(o,a,b) -> (lnum, Alu2(o,rebind_reg_in_op a,rebind_reg_in_op b))
        | PuPo(o,a) -> (lnum, PuPo(o,rebind_reg_in_op a))
        | Move2(o,a,b) -> (lnum, Move2(o,rebind_reg_in_op a, rebind_reg_in_op b))
        | Ctl3(o,a,b,c) -> (lnum, Ctl3(o,rebind_reg_in_op a, rebind_reg_in_op b, rebind_reg_in_op c))
        | Ctl2(o,a,b) -> (lnum, Ctl2(o,rebind_reg_in_op a, rebind_reg_in_op b))
        | Ctl1(o,a) -> (lnum, Ctl1(o,rebind_reg_in_op a))
        | x -> (lnum, x)
      end
  in
  List.map rebind_register_in_insn lines

let rec free_up_needed_registers lines needs good_registers bad_registers =
  match needs with
  | [] -> translate_body lines
  | hd :: tl -> begin
      match allocate_reg good_registers with
      | Some(r,left) -> free_up_needed_registers lines tl left bad_registers
      | None -> begin
          match allocate_reg bad_registers with
          | Some(r,left) ->
             (* Printf.printf "freeing up register %s\n" (regname r); *)
             let freed_up_code = free_up_register lines (regname r) in
             free_up_needed_registers freed_up_code tl good_registers left
          | None -> raise NotEnoughFreeRegisters
        end
    end

let rec rebind_needed_registers lines needs good_registers bad_registers =
  match needs with
  | [] -> lines
  | hd :: tl -> begin
      match allocate_reg good_registers with
      | Some(r,left) -> 
         let new_code = rebind_register lines hd (regname r) in
         rebind_needed_registers new_code tl left bad_registers
      | None -> begin
          match allocate_reg bad_registers with
          | Some(r,left) ->
             let new_code = rebind_register lines hd (regname r) in
             rebind_needed_registers new_code tl good_registers left
          | None -> raise NotEnoughFreeRegisters
        end
    end

let translate_function lines =
(*  begin
    match lines with
    | Ok(insn) :: rest -> Printf.printf "Translating to x86prime: %s\n" (Printer.print_insn insn)
    | _ -> ()
  end;
 *)
  let regs = (find_regs lines) in
  let free_caller_saves_regs = caller_saves land (lnot regs) in
  let free_callee_saves_regs = callee_saves land (lnot regs) in
(*
  print_regs "uses: " regs;
  print_regs "free caller_saves: " free_caller_saves_regs;
  print_regs "free callee_saves: " free_callee_saves_regs;
 *)

  let trial_run = translate_body lines in
  let regs2 = find_regs trial_run in
  let needs_r_a = (regs2 land r_a_mask) <> 0 in
  let needs_r_d = (regs2 land r_d_mask) <> 0 in
  let needs = match needs_r_a,needs_r_d with
    | false,false -> []
    | false,true -> ["%r_d"]
    | true,false -> ["%r_a"]
    | true,true -> ["%r_a"; "%r_d"]
  in
  try
    let code = free_up_needed_registers lines needs free_caller_saves_regs free_callee_saves_regs in
    rebind_needed_registers code needs free_caller_saves_regs free_callee_saves_regs
  with NotEnoughFreeRegisters -> begin
    let lnum = match lines with
    | [] -> 0
    | (l,_)::_ -> l in
    (lnum, Other("    ERROR: Not enough registers for this function")) :: lines
  end

let rec grab_first_function program =
  match program with
  | (ln, Ast.Fun_end) as insn :: rest -> ([insn],rest)
  | hd :: tl -> begin
      let (rest_of_fun, rest_of_prog) = grab_first_function tl in
      (hd :: rest_of_fun, rest_of_prog)
    end
  | _ -> [], []

let rec split_program_not_in_function acc_functions acc_rest program =
  match program with
  | (_, Ast.Function(_)) :: rest -> begin
        let func,rest = grab_first_function program in
        split_program_not_in_function (func :: acc_functions) acc_rest rest
      end
  | hd :: tl -> split_program_not_in_function acc_functions (hd :: acc_rest) tl
  | _ -> (List.rev acc_functions),(List.rev acc_rest)

let split_program program =
  split_program_not_in_function [] [] program

let join_program functions nonfunctions =
  List.append (List.flatten functions) nonfunctions

let rec translate_nonfunctions (lines : (int * Ast.line) list) =
  match lines with
  | (_, Ast.Quad(_)) | (_, Ast.Comm(_)) | (_, Ast.Align(_)) as insn :: tl -> 
      insn :: (translate_nonfunctions tl)
  | other :: tl -> translate_nonfunctions tl
  | [] -> []
;;
let translate program =
  let functions, nonfunctions = split_program program in
  let translated_functions = List.map translate_function functions in
  let translated_nonfunctions = translate_nonfunctions nonfunctions in
  let result = join_program translated_functions translated_nonfunctions in
  result
