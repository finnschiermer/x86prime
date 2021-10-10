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
    let source = Translate.translate source in
    let source = Assemble.prepare source in
    let oc = open_out ((Filename.chop_suffix !program_name ".s") ^ ".prime") in 
    print_lines oc source
