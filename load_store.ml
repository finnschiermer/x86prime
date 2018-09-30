exception Address_mode_conversion_failed

let rec convert_loop lines =
  let open Ast in
  match lines with
  | Ok(Alu2(LEA,_,_)) as insn :: other -> insn :: convert_loop other
  | Ok(Alu2(_,Reg(_),Reg(_))) as insn :: other -> insn::(convert_loop other)
  | Ok(Alu2(_,Imm(_),Reg(_))) as insn :: other -> insn::(convert_loop other)
  | Ok(Alu2(_,EaS(m),Reg(_))) as insn :: other -> (rewrite_to_load insn other)
  | Ok(Alu2(_,EaDS(d,m),Reg(_))) as insn :: other -> (rewrite_to_load insn other)
  | Ok(Alu2(_,cplx,Reg(_))) as insn :: other -> (inject_leaq insn other)
  | Ok(Alu2(_,Reg(_),EaS(m))) as insn :: other -> (rewrite_to_store insn other)
  | Ok(Alu2(_,Reg(_),EaDS(d,m))) as insn :: other -> (rewrite_to_store insn other)
  | Ok(Alu2(_,Reg(_),cplx)) as insn :: other -> (inject_leaq insn other)
  | Ok(Move2(_,Reg(_),Reg(_))) | Ok(Move2(_,Imm(_),Reg(_)))
    | Ok(Move2(_,EaS(_),Reg(_))) | Ok(Move2(_,EaDS(_,_),Reg(_))) 
    | Ok(Move2(_,Reg(_),EaS(_))) | Ok(Move2(_,Reg(_),EaDS(_,_))) as insn :: other -> insn::(convert_loop other)
  | Ok(Move2(_,cplx,Reg(_))) as insn :: other -> (inject_leaq insn other)
  | Ok(Move2(_,Reg(_),cplx)) as insn :: other -> (inject_leaq insn other)
  | Ok(Move2(_,Imm(_),cplx)) as insn :: other -> (inject_leaq insn other)
  | hd :: tl -> hd :: (convert_loop tl)
  | [] -> []

and rewrite_to_load insn tail =
  let open Ast in
  match insn with
  | Ok(Alu2(opc,EaS(m),reg)) ->
     Ok(Move2(MOV,EaS(m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,Reg("%r14"),reg)) 
         :: (convert_loop tail))
  | Ok(Alu2(opc,EaDS(d,m),reg)) ->
     Ok(Move2(MOV,EaDS(d,m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,Reg("%r14"),reg)) 
         :: (convert_loop tail))
  | _ -> raise Address_mode_conversion_failed

and inject_leaq insn tail =
  let open Ast in
  match insn with
  | Ok(Alu2(opc,cplx,Reg(r))) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Alu2(opc,EaS("%r15"),Reg(r))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Ok(Alu2(opc,Reg(r),cplx)) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Alu2(opc,Reg(r),EaS("%r15"))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Ok(Move2(opc,cplx,Reg(r))) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Move2(opc,EaS("%r15"),Reg(r))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Ok(Move2(opc,Reg(r),cplx)) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Ok(Move2(opc,Reg(r),EaS("%r15"))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Ok(Move2(opc,Imm(i),cplx)) -> begin
      let insn1 = Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let insn2 = Ok(Move2(opc,Imm(i),Reg("%r14"))) in
      let trigger = Ok(Move2(opc,Reg("%r14"),EaS("%r15"))) in
     insn1 :: insn2 ::(convert_loop (trigger :: tail))
    end
  | _ -> raise Address_mode_conversion_failed

and rewrite_to_store insn tail =
  let open Ast in
  match insn with
  | Ok(Alu2(opc,reg,EaS(m))) ->
     Ok(Move2(MOV,EaS(m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,reg,Reg("%r14")))
         :: (Ok(Move2(MOV,Reg("%r14"),EaS(m)))
             :: (convert_loop tail)))
  | Ok(Alu2(opc,reg,EaDS(d,m))) ->
     Ok(Move2(MOV,EaDS(d,m),Reg("%r14"))) 
     :: (Ok(Alu2(opc,reg,Reg("%r14")))
         :: (Ok(Move2(MOV,Reg("%r14"),EaDS(d,m)))
             :: (convert_loop tail)))
  | _ -> raise Address_mode_conversion_failed

let convert lines = 
  convert_loop lines

