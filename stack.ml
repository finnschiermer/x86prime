(* Very simple basic block transformation. *)
(* FIXME: Only takes push/pop into account *)
(* Should also handle direct adjustment of %rsp *)
(* and memory addressing relative to %rsp *)

let rec stack_change lines change =
  let open Ast in
  match lines with
  | Res.Ok(PuPo(PUSH,_)) :: others -> stack_change others (change - 8)
  | Res.Ok(PuPo(POP,_)) :: others -> stack_change others (change + 8)
  | Res.Ok(Alu2(_)) :: others | Res.Ok(Move2(_)) :: others | Res.Ok(Ignored(_)) :: others -> stack_change others change
  | _ :: _ -> change
  | [] -> change

let rec process_all_blocks lines =
  let adjustment = stack_change lines 0 in
  if adjustment = 0 then rewrite_block lines 0 None
  else if adjustment < 0 then process_push_block lines adjustment
  else  process_pop_block lines adjustment

and process_pop_block block adjustment =
  let sp_adjust = Res.Ok(Ast.Alu2(Ast.ADD,Ast.Imm(Printf.sprintf "%d" adjustment),Ast.Reg("%rsp"))) in
  rewrite_block block 0 (Some sp_adjust)

and process_push_block block adjustment =
  let sp_adjust = Res.Ok(Ast.Alu2(Ast.ADD,Ast.Imm(Printf.sprintf "%d" adjustment),Ast.Reg("%rsp"))) in
  sp_adjust :: (rewrite_block block (0 - 8 - adjustment) None)

and rewrite_block block curr_sp terminator =
  let open Ast in
  match block with
  | Res.Ok(PuPo(PUSH,reg)) :: rest -> 
     if curr_sp = 0 then
       Res.Ok(Move2(MOV,reg,EaS("%rsp"))) :: rewrite_block rest (curr_sp - 8) terminator
     else
       Res.Ok(Move2(MOV,reg,EaDS((Printf.sprintf "%d" (curr_sp)), "%rsp"))) :: rewrite_block rest (curr_sp - 8) terminator
  | Res.Ok(PuPo(POP,reg)) :: rest ->
     if curr_sp == 0 then
       Res.Ok(Move2(MOV,EaS("%rsp"),reg)) :: rewrite_block rest (curr_sp + 8) terminator
     else
       Res.Ok(Move2(MOV,EaDS((Printf.sprintf "%d" (curr_sp)), "%rsp"),reg)) :: rewrite_block rest (curr_sp + 8) terminator
  | (Res.Ok(Alu2(_)) as insn) :: rest | (Res.Ok(Move2(_)) as insn) :: rest | (Res.Ok(Ignored(_)) as insn) :: rest -> 
     insn :: rewrite_block rest curr_sp terminator
  | (Res.Ok(Ctl0(_)) as insn) :: rest | (Res.Ok(Ctl1(_)) as insn) :: rest | (Res.Ok(Ctl3(_)) as insn) :: rest -> begin
      match terminator with
      | None -> insn :: process_all_blocks rest
      | Some(term) -> term :: insn :: process_all_blocks rest
    end
  | a :: b -> a :: process_all_blocks b
  | [] -> []

let rec rewrite_calls lines =
  let open Ast in
  match lines with
  | Res.Ok(Ctl1(CALL,target)) :: others -> 
     Res.Ok(Ctl2(CALL,target,Reg("%r15"))) :: rewrite_calls others
  | Res.Ok(Ctl0(RET)) :: others ->
     Res.Ok(PuPo(POP,Reg("%r15"))) :: Res.Ok(Ctl1(RET,Reg("%r15"))) :: rewrite_calls others
  | Res.Ok(Fun_start) as insn :: others ->
     insn :: Res.Ok(PuPo(PUSH,Reg("%r15"))) :: rewrite_calls others
  | i :: others -> i :: rewrite_calls others
  | [] -> []


let elim_stack lines =
  process_all_blocks (rewrite_calls lines)
