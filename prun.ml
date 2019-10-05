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

(* performance controls *)
let p_type = ref "gshare"
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
let l2_idx_bits = ref 10
let l2_blk_bits = ref 5
let l2_latency = ref 12

let mem_latency = ref 100


let dec_latency = ref 1
let pipe_width = ref 1
let ooo = ref false

let print_cache_config assoc idx_bits blk_bits latency =
  let size = assoc lsl (idx_bits + blk_bits) in
  Printf.printf "    Size %d bytes\n" size;
  Printf.printf "    Associativity %d\n" assoc;
  Printf.printf "    Block-size %d bytes\n" (1 lsl blk_bits);
  Printf.printf "    Hit latency %d\n" latency

let print_config () =
  Printf.printf "Performance model configuration\n";
  if !ooo then Printf.printf "  Out-of-order execution\n" else Printf.printf "  In-order execution\n";
  Printf.printf "  Pipeline width %d insn/clk\n" !pipe_width;
  Printf.printf "  Branch predictor %s\n" (match !p_type with
    | "t" -> "always taken"
    | "nt" -> "always not taken"
    | "btfnt" -> "backward taken, forward not taken"
    | "oracle" -> "oracle (it knows!)"
    | "local" -> "local history (PC indexed)"
    | "gshare" -> "gshare (PC xor History indexed)"
    | _ -> "");
  Printf.printf "  Return predictor with %d entries\n" !p_ret_size;
  Printf.printf "  Decode/schedule latency %d stages\n" !dec_latency;
  Printf.printf "  Data-cache configuration\n";
  print_cache_config !d_assoc !d_idx_bits !d_blk_bits !d_latency;
  Printf.printf "  Instruction-cache configuration\n";
  print_cache_config !i_assoc !i_idx_bits !i_blk_bits !i_latency;
  Printf.printf "  L2 cache configuration\n";
  print_cache_config !l2_assoc !l2_idx_bits !l2_blk_bits !l2_latency;
  Printf.printf "  Main memory %d cycles away\n" !mem_latency

let run entry =
  match !labels with
  | None -> raise NoValidProgram
  | Some(env) -> begin
      match List.assoc_opt entry env with
      | None -> raise (UnknownEntryPoint entry)
      | Some(addr) -> begin
              Machine.set_ip !machine addr;
              let l2 = Cache.cache_create !l2_idx_bits !l2_blk_bits !l2_assoc !l2_latency (MainMemory !mem_latency) in
              let num_alus = if !pipe_width > 2 then !pipe_width - 1 else !pipe_width in
              let fd_queue_size = (1 + !i_latency + !dec_latency) * !pipe_width in
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
                  rp = Predictors.create_return_predictor !p_ret_size;
                  l2 = l2;
                  i = Cache.cache_create !i_idx_bits !i_blk_bits !i_assoc !i_latency (Cache l2);
                  d = Cache.cache_create !d_idx_bits !d_blk_bits !d_assoc !d_latency (Cache l2);
                  fetch_start = Resource.create "fetch-start" true !pipe_width 1000;
                  fetch_decode_q = Resource.create "fetch-decode" true fd_queue_size 10000;
                  rob = Resource.create "reorder buffer" true 128 10000;
                  alu = Resource.create "arithmetic" (not !ooo) num_alus 1000;
                  agen = Resource.create "agen" true 1 1000;
                  branch = Resource.create "branch-resolver" true 1 1000;
                  dcache = Resource.create "dcache" (not !ooo) 1 1000;
                  retire = Resource.create "retire" true 4 1000;
                  reg_ready = Array.make 16 0;
                  dec_lat = !dec_latency;
                  ooo = false;
                  perf_model = false
                } in
              Machine.run p_control !machine;
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
  if !do_print_config then print_config ();
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
