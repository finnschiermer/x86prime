let machine = ref (Machine.create ())
let labels = ref None
let program_name = ref ""
let tracefile_name = ref ""
let entry_name = ref ""
let args = ref []
let do_show = ref false
let do_print_config = ref false
let print_perf = ref false

exception NoValidProgram
exception UnknownEntryPoint of string
exception InvalidArgument of string

let run entry =
  match !labels with
  | None -> raise NoValidProgram
  | Some(env) -> begin
      match List.assoc_opt entry env with
      | None -> raise (UnknownEntryPoint entry)
      | Some(addr) -> begin
              Machine.set_ip !machine addr;
              Machine.run !machine
        end
    end

let set_pipe = ref ""
let set_mem = ref ""

exception UnimplementedOption of string

let cmd_spec = [
    ("-show", Arg.Set do_show, "show each simulation step");
    ("-tracefile", Arg.Set_string tracefile_name, "<name of file> create a trace file for later verfication");
  ]

let set_names s = 
  if !program_name = "" then program_name := s
  else if !entry_name = "" then entry_name := s
  else begin
    let arg = Int64.of_string_opt s in
    match arg with
      | Some(a) -> args := !args @ [a]
      | None -> raise (InvalidArgument "Wrong arguments. Must be <hex-file> <start-label> <args2program....>")
  end

let get_symbols fname =
  let ic = open_in fname in
  let ok = ref true in
  let symbols = ref [] in
  let f nm v = (nm, v) in
  while !ok do
    try
      let line = input_line ic in
      symbols := (Scanf.sscanf line "%s : %x" f) :: !symbols
    with
      _ -> ok := false
  done;
  !symbols

let get_hex fname =
  let ic = open_in fname in
  let ok = ref true in
  let lines = ref [] in
  let f addr insn = (addr, insn) in
  while !ok do
    try
      let line = input_line ic in
      lines := (Scanf.sscanf line "%x : %[0-9a-fA-F]" f) :: !lines
    with
      _ -> ok := false
  done;
  !lines

let () = 
  Arg.parse cmd_spec set_names "Simulate x86prime program from .hex format\n\n";
  if !program_name <> "" then begin
    let hex = get_hex !program_name in
    machine := Machine.init hex;
    if !tracefile_name <> "" then Machine.set_tracefile !machine (open_out !tracefile_name);
    if !do_show then Machine.set_show !machine;
    if !entry_name <> "" then begin
      labels := Some (get_symbols ((Filename.chop_suffix !program_name ".hex") ^ ".sym"));
      Machine.set_args !machine !args;
      run !entry_name
    end else raise (InvalidArgument "no valid start-label")
  end
  else Printf.printf "No program, doing nothing :-)\n"
