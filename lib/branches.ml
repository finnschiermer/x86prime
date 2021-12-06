exception Branch_conversion_failure_at of string

type generator_info = Unknown | Chosen of Ast.line | Conflict of string

let rewrite_bcc lnum condition (flag_setter : generator_info) =
  let open Ast in
  match condition, flag_setter with
  | Ctl1(Jcc(cond),lab), Chosen(Alu2(TEST,a,b)) -> (lnum, Ctl3(CBcc(Ast.rev_cond cond),Imm("0"),b,lab))
  | Ctl1(Jcc(cond),lab), Chosen(Alu2(CMP,a,b)) -> (lnum, Ctl3(CBcc(Ast.rev_cond cond),a,b,lab))
  | Ctl1(Jcc(cond),lab), Chosen(Alu2(op,a,b)) -> (lnum, Ctl3(CBcc(Ast.rev_cond cond),Imm("0"),b,lab))
  | Ctl1(Jcc(cond),lab), Unknown -> lnum, Other "    ERROR - cannot convert to prime"
  | insn,Conflict(lab) -> lnum, Other "    ERROR - cannot join control flow for this"
  | insn,_ -> (lnum, insn)

(* add a flag_setter to env at label - or check against one already registered *)
let unify_inbound_flow env (label : string) (flag_setter : generator_info) =
  match (List.assoc_opt label env),flag_setter with
  | Some(Chosen(setter)),Chosen(new_setter) -> begin
      if setter = new_setter then Chosen(setter)
      else begin
          match setter, new_setter with
            (* compare unifies if both compares are equal - is this redundant? *)
          | Alu2(CMP,a1,b1),Alu2(CMP,a2,b2) when (a1=a2 && b1=b2) -> Chosen(setter)
          | Alu2(CMP,_,_),_ -> Conflict(label)
          | _,Alu2(CMP,_,_) -> Conflict(label)
          | Alu2(_,_,d1),Alu2(_,_,d2) when d1=d2 -> Chosen(setter)
          | Alu2(_,_,d1),Move2(_,_,d2) when d1=d2 -> Chosen(setter)
          | Move2(_,_,d1),Alu2(_,_,d2) when d1=d2 -> Chosen(setter)
          | Move2(_,_,d1),Move2(_,_,d2) when d1=d2 -> Chosen(setter)
          | _ -> Conflict(label)
        end
    end
  | Some(x),Unknown -> x
  | Some(Unknown),x -> x
  | None,x -> x
  | _ -> Conflict(label)
 
let operand_conflicts target_op_spec other_insn =
  let open Ast in
  match target_op_spec, other_insn with
  | Reg(rt),Chosen(Alu2(_,Reg(rs),_)) -> if rt = rs then true else false
  | Reg(rt),Chosen(Alu2(_,_,Reg(rs))) -> if rt = rs then true else false
  | _ -> true (* something we don't know - so flag it *)

let rec fill_env_loop env lines (flag_setter : generator_info) =
  let open Ast in
  match lines with
  | (_, Label(lab)) :: others -> begin
      let resolution = unify_inbound_flow env lab flag_setter in
      fill_env_loop ((lab,resolution) :: env) others resolution
    end
  | (_, Ctl1(Jcc(_),EaD(lab))) :: others -> begin
      let resolution = unify_inbound_flow env lab flag_setter in
      fill_env_loop ((lab,resolution) :: env) others flag_setter
    end
  | (_, Ctl1(JMP,EaD(lab))) :: others -> begin
      let resolution = unify_inbound_flow env lab flag_setter in
      fill_env_loop ((lab,resolution) :: env) others Unknown
    end
  | (_, Alu2(LEA,_,_)) :: others -> fill_env_loop env others flag_setter
  | (_, (Alu2(_) as insn)) :: others -> fill_env_loop env others (Chosen(insn))
  | (_, Ctl1((_),_)) :: others | (_, Ctl0(_)) :: others -> fill_env_loop env others (Unknown : generator_info)
  | insn :: others -> fill_env_loop env others flag_setter
  | [] -> env

let labnum = ref 0

let next_lab_name _ =
  let num = !labnum in
  labnum := 1 + num;
  Printf.sprintf ".cmov_target_%d" num

let rec elim_loop env lines flag_setter =
  let open Ast in
  match lines with 
  | (lnum, insn) as line :: other_lines -> begin
      match insn with
      | Alu2(TEST,_,_) | Alu2(CMP,_,_) -> elim_loop env other_lines (Chosen insn)
      | Alu2(LEA,_,target) -> begin
          if operand_conflicts target flag_setter then
            line :: (elim_loop env other_lines Unknown)
          else
            line :: (elim_loop env other_lines flag_setter)
        end
      | Alu2(CMOVcc(cc),s,d) -> begin
          let labname = next_lab_name () in
          let lab = Label(labname) in
          let lines = (lnum, Ctl1(Jcc(Ast.rev_cond cc),EaD(labname))) :: (lnum, Move2(MOV,s,d)) :: (lnum, lab) :: other_lines in
          (elim_loop env lines flag_setter)
        end
      | Alu2(_)                        -> line :: (elim_loop env other_lines (Chosen insn))
      | Ctl0(RET) | Ctl1(CALL,_)       -> line :: (elim_loop env other_lines Unknown)
      | Ctl1(JMP,EaD(target)) -> begin
          if target.[0] = '.' then
            line :: (elim_loop env other_lines Unknown)
          else
            [(lnum, Other ("    ERROR - Cannot handle jmp to function (tail-call?)"))]
        end
      | Ctl1(Jcc(_),EaD(target)) -> begin
          (rewrite_bcc lnum insn flag_setter) :: (elim_loop env other_lines flag_setter)
        end
      | Label(lab) -> begin
          match (List.assoc_opt lab env) with
          | Some(setter) -> line :: (elim_loop env other_lines setter)
          | None -> line :: (elim_loop env other_lines Unknown)
        end
      | _ -> line :: (elim_loop env other_lines flag_setter)
    end
  | [] -> []
;;
let print_env oc env =
  let printer x =
    match x with
    | nm,Unknown -> Printf.fprintf oc "%s : Unknown\n" nm
    | nm,Chosen(insn) -> (Printf.fprintf oc "%s : " nm); (Printer.line_printer oc insn)
    | nm,Conflict(lab) -> (Printf.fprintf oc "%s : Conflict at %s\n" nm lab)
  in List.iter printer env

let elim_flags lines  =
  let env = fill_env_loop [] lines Unknown in
  elim_loop env lines Unknown

