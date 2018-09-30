(* Very simple basic block transformation. *)
(* FIXME: Only takes push/pop into account *)
(* Should also handle direct adjustment of %rsp *)
(* and memory addressing relative to %rsp *)

let rec stack_change lines pushes pops =
  let open Ast in
  match lines with
  | Ok(PuPo(PUSH,_)) :: others -> stack_change others (pushes + 1) pops
  | Ok(PuPo(POP,_)) :: others -> stack_change others pushes (pops + 1)
  | Ok(Alu2(_)) :: others | Ok(Move2(_)) :: others | Ok(Ignored(_)) :: others -> stack_change others pushes pops
  | _ :: _ -> pushes,pops
  | [] -> pushes,pops

exception PushAndPop

let rec process_all_blocks lines =
  let (pushes,pops) = stack_change lines 0 0 in
  if pushes = 0 && pops = 0 then rewrite_block lines 0 None
  else if pushes <> 0 && pops = 0 then process_push_block lines pushes
  else if pops <> 0 && pushes = 0 then process_pop_block lines pops
  else process_push_pop_block lines pushes pops

and process_pop_block block pops =
  let sp_adjust = Ok(Ast.Alu2(ADD,Ast.Imm(Printf.sprintf "%d" (8 * pops)),Ast.Reg("%rsp"))) in
  rewrite_block block 0 (Some sp_adjust)

and process_push_block block pushes =
  let sp_adjust = Ok(Ast.Alu2(SUB,Ast.Imm(Printf.sprintf "%d" (8 * pushes)),Ast.Reg("%rsp"))) in
  sp_adjust :: (rewrite_block block (8 * pushes) None)

and process_push_pop_block block pushes pops =
  let sp_adjust_before = Ok(Ast.Alu2(SUB,Ast.Imm(Printf.sprintf "%d" (8 * pushes)),Ast.Reg("%rsp"))) in
  let sp_adjust_after = Ok(Ast.Alu2(ADD,Ast.Imm(Printf.sprintf "%d" (8 * pops)),Ast.Reg("%rsp"))) in
  sp_adjust_before :: rewrite_block block (8 * pushes) (Some sp_adjust_after)

and rewrite_block block curr_sp terminator =
  let open Ast in
  match block with
  | Ok(PuPo(PUSH,reg)) :: rest -> 
     let curr_sp = curr_sp - 8 in
     if curr_sp = 0 then
       Ok(Move2(MOV,reg,EaS("%rsp"))) :: rewrite_block rest curr_sp terminator
     else
       Ok(Move2(MOV,reg,EaDS((Printf.sprintf "%d" (curr_sp)), "%rsp"))) :: rewrite_block rest curr_sp terminator
  | Ok(PuPo(POP,reg)) :: rest ->
     if curr_sp = 0 then
       Ok(Move2(MOV,EaS("%rsp"),reg)) :: rewrite_block rest (curr_sp + 8) terminator
     else
       Ok(Move2(MOV,EaDS((Printf.sprintf "%d" (curr_sp)), "%rsp"),reg)) :: rewrite_block rest (curr_sp + 8) terminator
  | (Ok(Alu2(_)) as insn) :: rest | (Ok(Move2(_)) as insn) :: rest | (Ok(Ignored(_)) as insn) :: rest -> 
     insn :: rewrite_block rest curr_sp terminator
  | (Ok(Ctl0(_)) as insn) :: rest | (Ok(Ctl1(_)) as insn) :: rest | (Ok(Ctl3(_)) as insn) :: rest -> begin
      match terminator with
      | None -> insn :: process_all_blocks rest
      | Some(term) -> term :: insn :: process_all_blocks rest
    end
  | a :: b -> a :: process_all_blocks b
  | [] -> []

let rec rewrite_calls lines =
  let open Ast in
  match lines with
  | Ok(Ctl1(CALL,target)) :: others -> 
     Ok(Ctl2(CALL,target,Reg("%r15"))) :: rewrite_calls others
  | Ok(Ctl0(RET)) :: others ->
     Ok(PuPo(POP,Reg("%r15"))) :: Ok(Ctl1(RET,Reg("%r15"))) :: rewrite_calls others
  | Ok(Fun_start) as insn :: others ->
     insn :: Ok(PuPo(PUSH,Reg("%r15"))) :: rewrite_calls others
  | i :: others -> i :: rewrite_calls others
  | [] -> []


let elim_stack lines =
  process_all_blocks (rewrite_calls lines)
