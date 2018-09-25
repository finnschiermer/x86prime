exception Address_mode_conversion_failed

let rec convert_loop lines =
  let open Ast in
  match lines with
  | Res.Ok(Alu2(LEA,_,_)) as insn :: other -> insn :: convert_loop other
  | Res.Ok(Alu2(_,Reg(_),Reg(_))) as insn :: other -> insn::(convert_loop other)
  | Res.Ok(Alu2(_,Imm(_),Reg(_))) as insn :: other -> insn::(convert_loop other)
  | Res.Ok(Alu2(_,EaS(m),Reg(_))) as insn :: other -> (rewrite_to_load insn other)
  | Res.Ok(Alu2(_,EaDS(d,m),Reg(_))) as insn :: other -> (rewrite_to_load insn other)
  | Res.Ok(Alu2(_,cplx,Reg(_))) as insn :: other -> (inject_leaq insn other)
  | Res.Ok(Alu2(_,Reg(_),EaS(m))) as insn :: other -> (rewrite_to_store insn other)
  | Res.Ok(Alu2(_,Reg(_),EaDS(d,m))) as insn :: other -> (rewrite_to_store insn other)
  | Res.Ok(Alu2(_,Reg(_),cplx)) as insn :: other -> (inject_leaq insn other)
  | Res.Ok(Move2(_,Reg(_),Reg(_))) | Res.Ok(Move2(_,Imm(_),Reg(_)))
    | Res.Ok(Move2(_,EaS(_),Reg(_))) | Res.Ok(Move2(_,EaDS(_,_),Reg(_))) 
    | Res.Ok(Move2(_,Reg(_),EaS(_))) | Res.Ok(Move2(_,Reg(_),EaDS(_,_))) as insn :: other -> insn::(convert_loop other)
  | Res.Ok(Move2(_,cplx,Reg(_))) as insn :: other -> (inject_leaq insn other)
  | Res.Ok(Move2(_,Reg(_),cplx)) as insn :: other -> (inject_leaq insn other)
  | hd :: tl -> hd :: (convert_loop tl)
  | [] -> []

and rewrite_to_load insn tail =
  let open Ast in
  match insn with
  | Res.Ok(Alu2(opc,EaS(m),reg)) ->
     Res.Ok(Move2(MOV,EaS(m),Reg("%r14"))) 
     :: (Res.Ok(Alu2(opc,Reg("%r14"),reg)) 
         :: (convert_loop tail))
  | Res.Ok(Alu2(opc,EaDS(d,m),reg)) ->
     Res.Ok(Move2(MOV,EaDS(d,m),Reg("%r14"))) 
     :: (Res.Ok(Alu2(opc,Reg("%r14"),reg)) 
         :: (convert_loop tail))
  | _ -> raise Address_mode_conversion_failed

and inject_leaq insn tail =
  let open Ast in
  match insn with
  | Res.Ok(Alu2(opc,cplx,Reg(r))) -> begin
      let insn1 = Res.Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Res.Ok(Alu2(opc,EaS("%r15"),Reg(r))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Res.Ok(Alu2(opc,Reg(r),cplx)) -> begin
      let insn1 = Res.Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Res.Ok(Alu2(opc,Reg(r),EaS("%r15"))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Res.Ok(Move2(opc,cplx,Reg(r))) -> begin
      let insn1 = Res.Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Res.Ok(Move2(opc,EaS("%r15"),Reg(r))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | Res.Ok(Move2(opc,Reg(r),cplx)) -> begin
      let insn1 = Res.Ok(Alu2(LEA,cplx,Reg("%r15"))) in
      let trigger = Res.Ok(Move2(opc,Reg(r),EaS("%r15"))) in
     insn1 :: (convert_loop (trigger :: tail))
    end
  | _ -> raise Address_mode_conversion_failed

and rewrite_to_store insn tail =
  let open Ast in
  match insn with
  | Res.Ok(Alu2(opc,reg,EaS(m))) ->
     Res.Ok(Move2(MOV,EaS(m),Reg("%r14"))) 
     :: (Res.Ok(Alu2(opc,reg,Reg("%r14")))
         :: (Res.Ok(Move2(MOV,Reg("%r14"),EaS(m)))
             :: (convert_loop tail)))
  | Res.Ok(Alu2(opc,reg,EaDS(d,m))) ->
     Res.Ok(Move2(MOV,EaDS(d,m),Reg("%r14"))) 
     :: (Res.Ok(Alu2(opc,reg,Reg("%r14")))
         :: (Res.Ok(Move2(MOV,Reg("%r14"),EaDS(d,m)))
             :: (convert_loop tail)))
  | _ -> raise Address_mode_conversion_failed

let convert lines = 
  convert_loop lines

