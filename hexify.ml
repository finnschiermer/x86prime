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

let line_mapper line =
  try
    let lexbuf = Lexing.from_string line in
    let p : Ast.line = Parser.aline Lexer.read lexbuf in
    Ok(p)
  with
  | Lexer.Error msg -> Error(msg, line)
  | _ -> Error("unknown insn", line)
;;

let parse_lines lines  =
  List.map line_mapper lines
;;

let print_lines oc lines =
  List.iter (Printer.line_printer oc) lines
;;
let do_txl = ref false
let do_asm = ref true
let do_list = ref true
let program_name = ref ""

let read fname =
  parse_lines (to_lines fname)

exception NoValidProgram
exception UnknownEntryPoint of string
exception InvalidArgument of string
exception UnimplementedOption of string

let set_file s = 
  program_name := s

let print_syms oc syms =
  let print_sym (lab,addr) = Printf.fprintf oc "%s : %s\n" lab addr in
  List.iter print_sym syms 

let () = 
  Arg.parse [] set_file "Encode .prime file (generate by 'primify') as .hex file\n\n";
  if not (Filename.check_suffix !program_name ".prime") then
    raise (InvalidArgument "Filename must end in '.prime'");
  if !program_name <> "" then begin
      Lexer.translating := false;
      let source = read !program_name in
      let source = Translate.translate source in
      let source = Assemble.prepare source in
      let prog,syms = Assemble.assemble source in
      let oc = open_out ((Filename.chop_suffix !program_name ".prime") ^ ".hex") in 
      Assemble.print_assembly oc prog;
      let oc = open_out ((Filename.chop_suffix !program_name ".prime") ^ ".sym") in
      print_syms oc syms
    end
  else Printf.printf "No program, doing nothing :-)\n"
