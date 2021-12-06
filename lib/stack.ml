(* Very simple basic block transformation. *)
(* FIXME: Only takes push/pop into account *)
(* Should also handle direct adjustment of %rsp *)
(* and memory addressing relative to %rsp *)

let rec stack_change lines pushes pops =
  let open Ast in
  match lines with
  | (_, PuPo(PUSH,_)) :: others -> stack_change others (pushes + 1) pops
  | (_, PuPo(POP,_)) :: others -> stack_change others pushes (pops + 1)
  | (_, Alu2(_)) :: others | (_, Move2(_)) :: others | (_, Ignored(_)) :: others -> stack_change others pushes pops
  | _ :: _ -> pushes,pops
  | [] -> pushes,pops

let rec process_all_blocks lnum lines =
  let (pushes,pops) = stack_change lines 0 0 in
  if pushes = 0 && pops = 0 then rewrite_block lines 0 None
  else if pushes <> 0 && pops = 0 then process_push_block lnum lines pushes
  else if pops <> 0 && pushes = 0 then process_pop_block lnum lines pops
  else process_push_pop_block lnum lines pushes pops

and process_pop_block lnum block pops =
  let sp_adjust = (lnum, Ast.Alu2(ADD,Ast.Imm(Printf.sprintf "%d" (8 * pops)),Ast.Reg("%rsp"))) in
  rewrite_block block 0 (Some sp_adjust)

and process_push_block lnum block pushes =
  let sp_adjust = (lnum, Ast.Alu2(SUB,Ast.Imm(Printf.sprintf "%d" (8 * pushes)),Ast.Reg("%rsp"))) in
  sp_adjust :: (rewrite_block block (8 * pushes) None)

and process_push_pop_block lnum block pushes pops =
  let sp_adjust_before = (lnum, Ast.Alu2(SUB,Ast.Imm(Printf.sprintf "%d" (8 * pushes)),Ast.Reg("%rsp"))) in
  let sp_adjust_after = (lnum, Ast.Alu2(ADD,Ast.Imm(Printf.sprintf "%d" (8 * pops)),Ast.Reg("%rsp"))) in
  sp_adjust_before :: rewrite_block block (8 * pushes) (Some sp_adjust_after)

and rewrite_block block curr_sp terminator =
  let open Ast in
  match block with
  | (lnum, PuPo(PUSH,reg)) :: rest -> 
     let curr_sp = curr_sp - 8 in
     if curr_sp = 0 then
       (lnum, Move2(MOV,reg,EaS("%rsp"))) :: rewrite_block rest curr_sp terminator
     else
       (lnum, Move2(MOV,reg,EaDS((Printf.sprintf "%d" (curr_sp)), "%rsp"))) :: rewrite_block rest curr_sp terminator
  | (lnum, PuPo(POP,reg)) :: rest ->
     if curr_sp = 0 then
       (lnum, Move2(MOV,EaS("%rsp"),reg)) :: rewrite_block rest (curr_sp + 8) terminator
     else
       (lnum, Move2(MOV,EaDS((Printf.sprintf "%d" (curr_sp)), "%rsp"),reg)) :: rewrite_block rest (curr_sp + 8) terminator
  | ((_, Alu2(_)) as insn) :: rest | ((_, Move2(_)) as insn) :: rest | ((_, Ignored(_)) as insn) :: rest -> 
     insn :: rewrite_block rest curr_sp terminator
  | ((_, Ctl0(_)) as insn) :: rest | ((_, Ctl1(_)) as insn) :: rest | ((_, Ctl3(_)) as insn) :: rest 
    | ((_, Label(_)) as insn) :: rest -> begin
      match terminator with
      | None -> insn :: process_all_blocks (-1) rest
      | Some(term) -> term :: insn :: process_all_blocks (-1) rest
    end
  | a :: b -> a :: process_all_blocks (-1) b
  | [] -> []

let rec rewrite_calls lines =
  let open Ast in
  match lines with
  | (lnum, Ctl1(CALL,target)) :: others -> 
     (lnum, Ctl2(CALL,target,Reg("%r11"))) :: rewrite_calls others
  | (lnum, Ctl0(RET)) :: others ->
     (lnum, PuPo(POP,Reg("%r11"))) :: (lnum, Ctl1(RET,Reg("%r11"))) :: rewrite_calls others
  | (lnum, Fun_start) as insn :: others ->
     insn :: (lnum, PuPo(PUSH,Reg("%r11"))) :: rewrite_calls others
  | i :: others -> i :: rewrite_calls others
  | [] -> []


let elim_stack lines =
  process_all_blocks (-1) (rewrite_calls lines)
