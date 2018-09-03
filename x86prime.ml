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
  | _ -> Error("failed: ", line)
;;

let parse_lines lines  =
  List.map line_mapper lines
;;

let print_lines lines =
  List.iter Printer.line_printer lines
;;
let assemble fname =
  let lines = parse_lines (to_lines fname) in
  let lines = Stack.elim_stack lines in
  let lines = (Branches.elim_flags (Load_store.convert lines)) in
  Assemble.assemble_lines lines

let cmd_spec = [("-f", Arg.String assemble, "name of file")]
let id _ = ()

let () = Arg.parse cmd_spec id "Transform gcc output to x86' and assemble"
