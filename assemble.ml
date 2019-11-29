(* Assemble our subset of x86 instructions (with extensions) *)

exception Error_during_assembly of string

type assem = Assembly of string * string * Ast.line | Source of Ast.line


let assemble_line env line : assem =
  let open Ast in
  match line with
  | Ok(insn) -> begin
      match Codec.assemble insn env with
      | Some(assembly) -> Assembly("?", assembly, insn)
      | None -> Source(insn)
    end
   | Error(s1,s2) -> raise (Error_during_assembly (String.concat " not prime: " [s1; s2]))

let should_translate line =
  let open Ast in
  match line with
  | Ok(Alu2(_)) | Ok(Move2(_)) | Ok(Ctl1(_)) | Ok(Ctl2(_)) | Ok(Ctl0(_)) | Ok(Ctl3(_)) 
  | Ok(Label(_)) | Ok(Quad(_)) | Ok(Comm(_)) | Ok(Align(_)) | Error(_) -> true
  | _ -> false

let print_assembly_line oc line =
  match line with
  | Assembly(a,s,i) -> Printf.fprintf oc "%8s : %-20s  #  " a s; (Printer.line_printer oc (Ok i))
  | Source(i) -> Printf.fprintf oc "NOT PRIME:                #  "; (Printer.line_printer oc (Ok i))

let print_assembly oc lines =
  List.iter (print_assembly_line oc) lines

let rec assign_addresses curr_add lines =
  match lines with
  | Assembly(_,encoding,Comm(nm,sz,aln)) :: rest -> begin
        let aligned = (curr_add + (aln - 1)) land (lnot (aln - 1)) in
        Assembly(Printf.sprintf "%08x" aligned, encoding, Comm(nm,sz,aln)) :: assign_addresses (aligned + sz) rest
      end
  | Assembly(_,encoding,Align(q)) :: rest -> begin
      let alignment = q in
      let aligned = (curr_add + (alignment - 1)) land (lnot (alignment - 1)) in
      Assembly(Printf.sprintf "%08x" aligned, encoding, Align(q)) :: assign_addresses aligned rest
    end
  | Assembly(_,encoding,Quad(q)) :: rest -> begin
      let alignment = 8 in
      let aligned = (curr_add + (alignment - 1)) land (lnot (alignment - 1)) in
      Assembly(Printf.sprintf "%08x" aligned, encoding, Quad(q)) :: assign_addresses (aligned + 8) rest
    end
  | Assembly(_,encoding,insn) :: rest -> 
     Assembly(Printf.sprintf "%08x" curr_add, encoding, insn) :: assign_addresses (curr_add + (String.length encoding) / 2) rest
  | s :: rest -> s :: assign_addresses curr_add rest
  | [] -> []

let rec gather_env env lines =
  match lines with
  | Assembly(addr, encoding, Ast.Label(lab)) :: rest -> gather_env ((lab, addr) :: env) rest
  | Assembly(addr, encoding, Ast.Comm(Expr(nm),sz,aln)) :: rest -> gather_env ((nm, addr) :: env) rest
  | s :: rest -> gather_env env rest
  | [] -> env

let rec print_env env =
  match env with
  | (a,b) :: tail -> Printf.printf "%s -> %s\n" a b; print_env tail
  | [] -> ()

let prepare lines = List.filter should_translate lines

let first_pass lines =
  let first_pass = List.map (assemble_line []) lines in
  let located = assign_addresses 0 first_pass in
  let env = gather_env [] located in
  env

let second_pass env lines =
  let second_pass = List.map (assemble_line env) lines in
  assign_addresses 0 second_pass

let get_line_as_hex line =
  match line with
  | Assembly(a,s,_) -> (a,s)
  | Source(i) -> raise (Error_during_assembly (Printf.sprintf "Not a valid x86prime instruction: %s" (Printer.print_insn i)))

let get_as_hex lines : (string * string) list =
  List.map get_line_as_hex lines

let assemble lines =
  let lines = prepare lines in
  let env = first_pass lines in
  let prog = second_pass env lines in
  prog, env
