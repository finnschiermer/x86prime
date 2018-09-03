exception Address_mode_conversion_failed

let rec convert_loop lines =
  let open Ast in
  match lines with
  | Ok(Alu2(LEA,_,_)) as insn :: other -> insn :: convert_loop other
  | Ok(Alu2(_,Reg(_),Reg(_))) as insn :: other -> insn::(convert_loop other)
  | Ok(Alu2(_,Imm(_),Reg(_))) as insn :: other -> insn::(convert_loop other)
  | Ok(Alu2(_,Ea1(m),Reg(_))) as insn :: other -> (rewrite_to_load insn other)
  | Ok(Alu2(_,Ea1b(d,m),Reg(_))) as insn :: other -> (rewrite_to_load insn other)
  | Ok(Alu2(_,cplx,Reg(_))) as insn :: other -> (inject_leaq insn other)
  | Ok(Alu2(_,Reg(_),Ea1(m))) as insn :: other -> (rewrite_to_store insn other)
  | Ok(Alu2(_,Reg(_),Ea1b(d,m))) as insn :: other -> (rewrite_to_store insn other)
  | Ok(Alu2(_,Reg(_),cplx)) as insn :: other -> (inject_leaq insn other)
  | Ok(Move2(_,Reg(_),Reg(_))) | Ok(Move2(_,Imm(_),Reg(_)))
    | Ok(Move2(_,Ea1(_),Reg(_))) | Ok(Move2(_,Ea1b(_,_),Reg(_))) 
    | Ok(Move2(_,Reg(_),Ea1(_))) | Ok(Move2(_,Reg(_),Ea1b(_,_))) as insn :: other -> insn::(convert_loop other)
  | Ok(Move2(_,cplx,Reg(_))) as insn :: other -> (inject_leaq insn other)
  | Ok(Move2(_,Reg(_),cplx)) as insn :: other -> (inject_leaq insn other)
  | hd :: tl -> hd :: (convert_loop tl)
  | [] -> []

and rewrite_to_load insn tail =
  let open Ast in
  match insn with
  | Ok(Alu2(opc,Ea1(m),reg)) ->
     Ok(Move2(MOV,Ea1(m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,Reg("%r14"),reg)) 
         :: (convert_loop tail))
  | Ok(Alu2(opc,Ea1b(d,m),reg)) ->
     Ok(Move2(MOV,Ea1b(d,m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,Reg("%r14"),reg)) 
         :: (convert_loop tail))
  | _ -> raise Address_mode_conversion_failed

and inject_leaq insn tail =
  let open Ast in
  match insn with
  | Ok(Alu2(opc,cplx,Reg(r))) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Alu2(opc,Ea1("%r15"),Reg(r))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Ok(Alu2(opc,Reg(r),cplx)) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Alu2(opc,Reg(r),Ea1("%r15"))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Ok(Move2(opc,cplx,Reg(r))) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Move2(opc,Ea1("%r15"),Reg(r))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Ok(Move2(opc,Reg(r),cplx)) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Move2(opc,Reg(r),Ea1("%r15"))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | _ -> raise Address_mode_conversion_failed

and rewrite_to_store insn tail =
  let open Ast in
  match insn with
  | Ok(Alu2(opc,reg,Ea1(m))) ->
     Ok(Move2(MOV,Ea1(m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,reg,Reg("%r14")))
         :: (Ok(Move2(MOV,Reg("%r14"),Ea1(m)))
             :: (convert_loop tail)))
  | Ok(Alu2(opc,reg,Ea1b(d,m))) ->
     Ok(Move2(MOV,Ea1b(d,m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,reg,Reg("%r14")))
         :: (Ok(Move2(MOV,Reg("%r14"),Ea1b(d,m)))
             :: (convert_loop tail)))
  | _ -> raise Address_mode_conversion_failed

let convert lines = 
  convert_loop lines

