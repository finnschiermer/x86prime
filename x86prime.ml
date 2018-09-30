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
let program_name = ref ""
let tracefile_name = ref ""
let entry_name = ref ""
let do_txl = ref false
let do_asm = ref false
let do_list = ref false
let do_show = ref false

let read fname =
  parse_lines (to_lines fname)

let translate lines =
  let lines = Stack.elim_stack lines in
  Branches.elim_flags (Load_store.convert lines)

let assemble lines =
  let lines = Assemble.prepare lines in
  let env = Assemble.first_pass lines in
  let prog = Assemble.second_pass env lines in
  let hex = Assemble.get_as_hex prog in begin
      program := Some prog;
      labels := Some env;
      if !do_list then Assemble.print_assembly prog;
      machine := Machine.init hex
    end

exception NoValidProgram
exception UnknownEntryPoint of string
exception InvalidArgument of string

(* performance controls *)
let p_type = ref "t"
let p_idx_size = ref 12
let p_ret_size = ref 8

let d_assoc = ref 4
let d_idx_bits = ref 7
let d_blk_bits = ref 5
let d_latency = ref 3

let i_assoc = ref 4
let i_idx_bits = ref 7
let i_blk_bits = ref 5
let i_latency = ref 3

let l2_assoc = ref 4
let l2_idx_bits = ref 11
let l2_blk_bits = ref 5
let l2_latency = ref 16

let mem_latency = ref 100

let run entry =
  match !labels with
  | None -> raise NoValidProgram
  | Some(env) -> begin
      match List.assoc_opt entry env with
      | None -> raise (UnknownEntryPoint entry)
      | Some(addr) -> begin
          Scanf.sscanf addr "%x" (fun x ->
              Machine.set_ip !machine x;
              let p_control : Machine.perf = {
                  bp = begin match !p_type with
                       | "t" -> Predictors.create_taken_predictor ()
                       | "nt" -> Predictors.create_not_taken_predictor ()
                       | "btfnt" -> Predictors.create_btfnt_predictor ()
                       | "oracle" -> Predictors.create_oracle_predictor ()
                       | "local" -> Predictors.create_local_predictor !p_idx_size
                       | "gshare" -> Predictors.create_gshare_predictor !p_idx_size
                       | _ -> raise (InvalidArgument !p_type)
                       end;
                  rp = Predictors.create_return_predictor !p_ret_size
                } in
              Machine.run p_control !machine;
              let tries,hits = Predictors.predictor_get_results p_control.bp in
              Printf.printf "Branch predictions %d   hits %d\n" tries hits;
              let tries,hits = Predictors.predictor_get_results p_control.rp in
              Printf.printf "Return predictions %d   hits %d\n" tries hits
            )
        end
    end

let cmd_spec = [
    ("-f", Arg.Set_string program_name, "<name of file> translates and assembles file");
    ("-txl", Arg.Set do_txl, "transform gcc output to x86prime");
    ("-asm", Arg.Set do_asm, "assemble x86prime into byte stream");
    ("-list", Arg.Set do_list, "list (transformed and/or assembled) program");
    ("-show", Arg.Set do_show, "show each simulation step (requires -run)");
    ("-tracefile", Arg.Set_string tracefile_name, "<name of file> create a trace file for later verification (requires -run)");
    ("-run", Arg.Set_string entry_name, "<name of function> starts simulation at indicated function (requires -asm)");
    ("-bp_type", Arg.Set_string p_type, "t/nt/btfnt/oracle/local/gshare select type of branch predictor");
    ("-bp_size", Arg.Set_int p_idx_size, "<size> select number of bits used to index branch predictor");
    ("-rp_size", Arg.Set_int p_ret_size, "<size> select number of entries in return predictor");
    ("-mem_lat", Arg.Set_int mem_latency, "<clks> number of clock cycles to read from main memory");
    ("-d_assoc", Arg.Set_int d_assoc, "<assoc> associativity of L1 D-cache");
    ("-d_lat", Arg.Set_int d_latency, "<latency> latency of L1 D-cache read");
    ("-d_idx_sz", Arg.Set_int d_idx_bits, "<size> number of bits used for indexing L1 D-cache");
    ("-d_blk_sz", Arg.Set_int d_blk_bits, "<size> number of bits used to address byte in block of L1 D-cache");
  ]

let id s = 
  Printf.printf "Unknown argument '%s' - run with -h for help\n" s;
  raise (InvalidArgument s)

let () = 
  Arg.parse cmd_spec id "Transform gcc output to x86', assemble and simulate\n\n";
  if !program_name <> "" then begin
      Lexer.translating := !do_txl;
      let source = read !program_name in
      let source = if !do_txl then translate source else source in
      let source = Assemble.prepare source in
      if !do_asm then assemble source else if !do_list then print_lines source;
      if !tracefile_name <> "" then Machine.set_tracefile !machine (open_out !tracefile_name);
      if !do_show then Machine.set_show !machine;
      if !entry_name <> "" then run !entry_name;
    end
  else Printf.printf "Error: you must give a program file name using -f\n"
