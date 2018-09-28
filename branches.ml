exception Cannot_unify_at of string

type generator_info = Unknown | Chosen of Ast.line | Conflict of string

let rewrite_bcc condition (flag_setter : generator_info) =
  let open Ast in
  match condition, flag_setter with
  | Ctl1(Jcc(cond),lab), Chosen(Alu2(TEST,a,b)) -> Ctl3(CBcc(Ast.rev_cond cond),Imm("0"),b,lab)
  | Ctl1(Jcc(cond),lab), Chosen(Alu2(CMP,a,b)) -> Ctl3(CBcc(Ast.rev_cond cond),a,b,lab)
  | Ctl1(Jcc(cond),lab), Unknown -> raise (Cannot_unify_at "unknown")
  | insn,Conflict(lab) -> raise (Cannot_unify_at lab)
  | insn,_ -> insn

(* add a flag_setter to env at label - or check against one already registered *)
let unify_inbound_flow env (label : string) (flag_setter : generator_info) =
  match (List.assoc_opt label env),flag_setter with
  | Some(Chosen(setter)),Chosen(new_setter) -> begin
      if setter = new_setter then Chosen(setter)
      else Conflict(label)
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
  | Ok(Label(lab)) :: others -> begin
      let resolution = unify_inbound_flow env lab flag_setter in
      fill_env_loop ((lab,resolution) :: env) others resolution
    end
  | Ok(Ctl1(Jcc(_),EaD(lab))) :: others | Ok(Ctl1(JMP,EaD(lab))) :: others -> begin
      let resolution = unify_inbound_flow env lab flag_setter in
      fill_env_loop ((lab,resolution) :: env) others flag_setter
    end
  | Ok(Alu2(LEA,_,_)) :: others -> fill_env_loop env others flag_setter
  | Ok(Alu2(_) as insn) :: others -> fill_env_loop env others (Chosen(insn))
  | Ok(Ctl1((_),_)) :: others | Ok(Ctl0(_)) :: others -> fill_env_loop env others (Unknown : generator_info)
  | insn :: others -> fill_env_loop env others flag_setter
  | [] -> env

let rec elim_loop env lines flag_setter =
  let open Ast in
  match lines with 
  | Ok(insn) as line :: other_lines -> begin
      match insn with
      | Alu2(TEST,_,_) | Alu2(CMP,_,_) -> elim_loop env other_lines (Chosen insn)
      | Alu2(LEA,_,target) -> begin
          if operand_conflicts target flag_setter then
            line :: (elim_loop env other_lines Unknown)
          else
            line :: (elim_loop env other_lines flag_setter)
        end
      | Alu2(_)                        -> line :: (elim_loop env other_lines (Chosen insn))
      | Ctl0(RET) | Ctl1(CALL,_)       -> line :: (elim_loop env other_lines Unknown)
      | Ctl1(Jcc(_),EaD(target)) -> begin
          (Ok (rewrite_bcc insn flag_setter)) :: (elim_loop env other_lines flag_setter)
        end
      | Label(lab) -> begin
          match (List.assoc_opt lab env) with
          | Some(setter) -> line :: (elim_loop env other_lines setter)
          | None -> line :: (elim_loop env other_lines Unknown)
        end
      | _ -> line :: (elim_loop env other_lines flag_setter)
    end
  | line :: other_lines -> line :: (elim_loop env other_lines flag_setter)
  | [] -> []
;;
let print_env env =
  let printer x =
    match x with
    | nm,Unknown -> Printf.printf "%s : Unknown\n" nm
    | nm,Chosen(insn) -> (Printf.printf "%s : " nm); (Printer.line_printer (Ok(insn)))
    | nm,Conflict(lab) -> (Printf.printf "%s : Conflict at %s\n" nm lab)
  in List.iter printer env

let elim_flags lines  =
  let env = fill_env_loop [] lines Unknown in
  elim_loop env lines Unknown

