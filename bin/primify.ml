open Prime
;;

(* Split file into list of text blocks according to line separators *)
let to_lines fname =
  let ch = open_in fname in
  let parsing = ref true in
  let lines = ref [] in
  while !parsing do
    try
      lines := (input_line ch) :: !lines
    with
      End_of_file -> parsing := false
  done;
  List.rev !lines
;;

let line_mapper line_num line =
  try
    line_num := 1 + !line_num;
    let lexbuf = Lexing.from_string line in
    let p : Ast.line = Parser.aline Lexer.read lexbuf in
    Ok(!line_num, p)
  with
  | Lexer.Error msg -> Error(msg, line)
  | _ -> Error("unknown insn", line)
;;

(* Parse list of text blocks into list of ASTs (or error) *)
let parse_lines lines  =
  let line_num = ref 0 in
  List.map (line_mapper line_num) lines
;;

let print_lines oc lines =
  List.iter (Printer.line_printer oc) lines

let print_unpaired_asm = Printer.print_unpaired_asm

let print_unpaired_src = Printer.print_unpaired_src

let print_paired = Printer.print_paired

let rec print_lines_ordered oc assembled source =
  match assembled, source with
  | [], [] -> ()
  | [], src :: src_rest -> begin print_unpaired_src oc src; print_lines_ordered oc [] src_rest end
  | ass :: ass_rest, [] -> begin print_unpaired_asm oc ass; print_lines_ordered oc ass_rest [] end
  | ass :: ass_rest, src :: src_rest -> 
      begin
        match ass,src with
        | Ok(ass_ln, _ ), Ok(src_ln, _) ->
          begin
            if ass_ln < src_ln then begin print_unpaired_asm oc ass; print_lines_ordered oc ass_rest source end;
            if ass_ln > src_ln then begin print_unpaired_src oc src; print_lines_ordered oc assembled src_rest end;
            if ass_ln = src_ln then begin print_paired oc ass src; print_lines_ordered oc ass_rest src_rest end
          end
        | _ -> ()
      end
;;
let do_txl = ref true
let do_asm = ref false
let do_list = ref true
let program_name = ref ""

(* Parse entire file into list of ASTs *)
let read fname =
  parse_lines (to_lines fname)

exception NoValidProgram
exception UnknownEntryPoint of string
exception InvalidArgument of string
exception UnimplementedOption of string

let set_file s = 
  program_name := s

let () = 
  Arg.parse [] set_file "Transform .s files (generate by 'gcc -Og -S <fname.c>') to .prime files\n\n";
  if not (Filename.check_suffix !program_name ".s") then
    raise (InvalidArgument "Filename not given or does not end with '.s'");
    Lexer.translating := true;
    let source = read !program_name in
    let translated = Translate.translate source in
    let assembled = Assemble.prepare translated in
    let oc = open_out ((Filename.chop_suffix !program_name ".s") ^ ".prime") in 
    print_lines_ordered oc assembled source

