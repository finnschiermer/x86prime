open Prime
;;

let labels = ref None
let program_name = ref ""
let tracefile_name = ref ""
let args = ref []
let entry_name = ref ""
let do_show = ref (-1)
let exec_limit = ref (-1)
let do_print_config = ref false
let print_perf = ref true

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

let pipe_width = ref 1
let ooo = ref false
let profile = ref false
let ooo_size = ref 512
let print_cache_config assoc idx_bits blk_bits latency =
  let size = assoc lsl (idx_bits + blk_bits) in
  Printf.printf "    Size %d bytes\n" size;
  Printf.printf "    Associativity %d\n" assoc;
  Printf.printf "    Block-size %d bytes\n" (1 lsl blk_bits);
  Printf.printf "    Hit latency %d\n" latency

let get_dec_lat = function
  | 1 -> 1
  | 2 | 3 -> 2
  | 4 | 5 -> 3
  | _ -> 4

let print_config () =
  Printf.printf "Performance model configuration\n";
  if !ooo then
    Printf.printf "  Out-of-order execution with windows size = %d\n" !ooo_size
  else 
    Printf.printf "  In-order execution\n";
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
  Printf.printf "  Decode/schedule latency %d stages\n" (get_dec_lat !pipe_width);
  Printf.printf "  Data-cache configuration\n";
  print_cache_config !d_assoc !d_idx_bits !d_blk_bits !d_latency;
  Printf.printf "  Instruction-cache configuration\n";
  print_cache_config !i_assoc !i_idx_bits !i_blk_bits !i_latency;
  Printf.printf "  L2 cache configuration\n";
  print_cache_config !l2_assoc !l2_idx_bits !l2_blk_bits !l2_latency;
  Printf.printf "  Main memory %d cycles away\n" !mem_latency

let prepare machine entry =
  match !labels with
  | None -> raise NoValidProgram
  | Some(env) -> begin
      match List.assoc_opt entry env with
      | None -> raise (UnknownEntryPoint entry)
      | Some(addr) -> begin
              Machine.set_ip machine addr;
              let l2 = Cache.cache_create !l2_idx_bits !l2_blk_bits !l2_assoc !l2_latency (MainMemory !mem_latency) in
              let num_alus = if !ooo && !pipe_width > 2 then !pipe_width - 1 else !pipe_width in
              let num_mem = if !pipe_width > 2 then !pipe_width / 2 else 1 in
              let dec_latency = get_dec_lat !pipe_width in
              let id_latency = (!i_latency + dec_latency) in
              let fd_queue_size = id_latency * !pipe_width in
              let alu_resource = Resource.create "arithmetic" (not !ooo) num_alus 1000 in
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
                  rob = Resource.create "reorder buffer" true !ooo_size 10000;
                  alu = alu_resource;
                  agen = if !ooo then Resource.create "agen" (not !ooo) num_mem 1000 else alu_resource;
                  branch = if !ooo then Resource.create "branch-resolver" true 1 1000 else alu_resource;
                  dcache = Resource.create "dcache" (not !ooo) num_mem 1000;
                  retire = Resource.create "retire" true !pipe_width 1000;
                  reg_ready = Array.make 16 0;
                  dec_lat = dec_latency;
                  ooo = !ooo;
                  perf_model = true;
                  profile = !profile;
                } in
              p_control
          end
    end
        ;;
let print_summary (p_control : Machine.perf) = begin
  if !print_perf then begin
    let tries,miss = Predictors.predictor_get_results p_control.bp in
    let mr = (float_of_int miss) /. (float_of_int (tries)) in
    Printf.printf "\n\nBranch predictions: %8d   miss %8d    missrate: %f\n" tries miss mr;
    let tries,miss = Predictors.predictor_get_results p_control.rp in
    let mr = (float_of_int miss) /. (float_of_int (tries)) in
    Printf.printf "Return predictions: %8d   miss %8d    missrate: %f\n" tries miss mr;
    let r,w,m = Cache.cache_get_stats p_control.l2 in
    let mr = (float_of_int m) /. (float_of_int (r+w)) in
    Printf.printf "L2-Cache reads: %8d   writes: %8d   miss: %8d   missrate: %f\n" r w m mr;
    let r_i,w,m = Cache.cache_get_stats p_control.i in
    let mr = (float_of_int m) /. (float_of_int (r_i+w)) in
    Printf.printf "I-Cache reads:  %8d   writes: %8d   miss: %8d   missrate: %f\n" r_i w m mr;
    let r,w,m = Cache.cache_get_stats p_control.d in
    let mr = (float_of_int m) /. (float_of_int (r+w)) in
    Printf.printf "D-Cache reads:  %8d   writes: %8d   miss: %8d   missrate: %f\n" r w m mr;
    let finished = Resource.get_earliest p_control.retire in
    Printf.printf "Execution finished after %d insn at cycle %d (CPI = %f)\n" r_i finished 
                  ((float_of_int finished) /. (float_of_int r_i))
  end
end

let run machine entry =
  let p_control = prepare machine entry in
  Machine.run p_control machine;
  print_summary p_control


let set_pipe = ref ""
let set_mem = ref ""

exception UnimplementedOption of string

let process_a3_options _ = 
  begin
    match !set_mem with
    | "" | "real" -> ()
    | "magic" -> begin
        mem_latency := 0;
        l2_latency := 0;
      end
    | "epic" -> begin
        d_latency := 1;
        i_latency := 1;
        l2_latency := 0;
        mem_latency := 0;
      end
    | _ -> raise (UnimplementedOption ("-mem " ^ !set_mem))
  end

let cmd_spec = [
    ("-show", Arg.Set_int do_show, "after <num> insn, show each simulation step");
    ("-limit", Arg.Set_int exec_limit, "limit number of simulated instructions");
    ("-bp_type", Arg.Set_string p_type, "t/nt/btfnt/oracle/local/gshare select type of branch predictor");
    ("-bp_size", Arg.Set_int p_idx_size, "<size> select number of bits used to index branch predictor");
    ("-rp_size", Arg.Set_int p_ret_size, "<size> select number of entries in return predictor");
    ("-mem_lat", Arg.Set_int mem_latency, "<clks> number of clock cycles to read from main memory");
    ("-d_assoc", Arg.Set_int d_assoc, "<assoc> associativity of L1 D-cache");
    ("-d_lat", Arg.Set_int d_latency, "<latency> latency of L1 D-cache read");
    ("-d_idx_sz", Arg.Set_int d_idx_bits, "<size> number of bits used for indexing L1 D-cache");
    ("-d_blk_sz", Arg.Set_int d_blk_bits, "<size> number of bits used to address byte in block of L1 D-cache");
    ("-i_assoc", Arg.Set_int i_assoc, "<assoc> associativity of L1 I-cache");
    ("-i_lat", Arg.Set_int i_latency, "<latency> latency of L1 I-cache read");
    ("-i_idx_sz", Arg.Set_int i_idx_bits, "<size> number of bits used for indexing L1 I-cache");
    ("-i_blk_sz", Arg.Set_int i_blk_bits, "<size> number of bits used to address byte in block of L1 I-cache");
    ("-l2_assoc", Arg.Set_int l2_assoc, "<assoc> associativity of L2 cache");
    ("-l2_lat", Arg.Set_int l2_latency, "<latency> latency of L2 cache read");
    ("-l2_idx_sz", Arg.Set_int l2_idx_bits, "<size> number of bits used for indexing L2 cache");
    ("-l2_blk_sz", Arg.Set_int l2_blk_bits, "<size> number of bits used to address byte in block of L2 cache");
    ("-width", Arg.Set_int pipe_width, "<width> max number of insn/clk");
    ("-ooo", Arg.Set ooo, "enable out-of-order scheduling");
    ("-ooo_sz", Arg.Set_int ooo_size, "size of out-of-order scheduling window");
    ("-profile", Arg.Set profile, "print an execution profile");
    ("-mem", Arg.Set_string set_mem, "magic/real select base memory configuration");
    ("-print_config", Arg.Set do_print_config, "print detailed performance model configuration")
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
  process_a3_options ();
  if !do_print_config then print_config ();
  if !program_name <> "" then begin
    let hex = get_hex !program_name in
    let machine = Machine.init hex in
    if !tracefile_name <> "" then Machine.set_tracefile machine (open_out !tracefile_name);
    if !entry_name <> "" then begin
      labels := Some (get_symbols ((Filename.chop_suffix !program_name ".hex") ^ ".sym"));
      let p_control = prepare machine !entry_name in
      Machine.set_args machine !args;
      let running = ref true in
      if !do_show > 0 then begin
        Machine.set_limit machine !do_show;
        Machine.runloop p_control machine;
        running := Machine.is_running machine
      end;
      if !do_show > (-1) then Machine.set_show machine;
      Machine.set_limit machine !exec_limit;
      if !running then Machine.runloop p_control machine;
      Machine.cleanup p_control machine;
      print_summary p_control
    end else raise (InvalidArgument "no valid start-label")
  end
  else Printf.printf "No program, doing nothing :-)\n"
