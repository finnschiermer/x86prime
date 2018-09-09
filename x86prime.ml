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
let machine = ref (Machine.create ())
let labels = ref None
let program = ref None

let assemble fname =
  let lines = parse_lines (to_lines fname) in
  let lines = Stack.elim_stack lines in
  let lines = (Branches.elim_flags (Load_store.convert lines)) in
  let lines = Assemble.prepare lines in
  let env = Assemble.first_pass lines in
  let prog = Assemble.second_pass env lines in
  let hex = Assemble.get_as_hex prog in begin
    (*  Assemble.print_assembly program;  *)
      program := Some prog;
      labels := Some env;
      machine := Machine.init hex
    end

exception NoValidProgram
exception UnknownEntryPoint of string

let run entry =
  match !labels with
  | None -> raise NoValidProgram
  | Some(env) -> begin
      match List.assoc_opt entry env with
      | None -> raise (UnknownEntryPoint entry)
      | Some(addr) -> begin
          Scanf.sscanf addr "%x" (fun x ->
              Printf.printf "Starting execution from address %X\n" x;
              Machine.set_ip !machine x;
              Machine.run !machine
            )
        end
    end

let set_show () = Machine.set_show !machine

let list () =
  match !program with
  | Some(prog) -> Assemble.print_assembly prog
  | None -> raise NoValidProgram

let set_tracefile fname =
  Machine.set_tracefile !machine (open_out fname)

let cmd_spec = [
    ("-f", Arg.String assemble, "<name of file> translates and assembles file");
    ("-list", Arg.Unit list, "list transformed and assembled program");
    ("-show", Arg.Unit set_show, "show each simulation step");
    ("-tracefile", Arg.String set_tracefile, "<name of file> create a trace file for later verification");
    ("-run", Arg.String run, "<name of function> starts simulation at indicated position (function)")]

let id _ = ()

let () = Arg.parse cmd_spec id "Transform gcc output to x86', assemble and simulate\n\nOptions must be given in order"
