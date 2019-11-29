
type memory = (Int64.t, (Int64.t array)) Hashtbl.t
type registers = Int64.t array
type perf = { 
    bp : Predictors.predictor;
    rp : Predictors.predictor;
    l2 : Cache.cache;
    i : Cache.cache;
    d : Cache.cache;
    fetch_start : Resource.resource;
    fetch_decode_q : Resource.resource;
    rob : Resource.resource;
    alu : Resource.resource;
    agen : Resource.resource;
    branch : Resource.resource;
    dcache : Resource.resource;
    retire : Resource.resource;
    reg_ready : int array;
    dec_lat : int;
    ooo : bool;
    perf_model : bool;
    profile : bool
  }

type event = Event of int * char
type plotline = {
    mutable count : int;
    mutable disasm : string;
    mutable iptr : int;
    mutable events : event list;
    mutable result : string;
    mutable first_cycle : int;
    mutable last_cycle : int;
  }

type insn_info = {
    mutable decoded : Ast.line option;
    mutable disasm : string;
    mutable encoding : string;
    mutable size : int;
    mutable count : int;
    mutable exe_latency : int;
    mutable time_change : int;
    mutable is_target : bool
  }

let no_insn : insn_info = { 
    decoded = None; disasm = ""; encoding = "";
    size = 0; count = 0; 
    exe_latency = 0; 
    time_change = 0; 
    is_target = false
  }

type state = {
    mutable show : bool;
    mutable running : bool;
    mutable info : insn_info; (* current instruction *)
    mutable ops : int list;
    mutable ims : int list;
    mutable tracefile : out_channel option;
    mutable ip : Int64.t;
    mutable message : string option;
    mutable profile : insn_info array;
    mutable is_target : bool;
    plot : plotline;
    regs : registers;
    mem : Memory.t;
  }

let create () = 
  let machine = { 
      show = false; 
      running = false;
      tracefile = None;
      info = no_insn;
      ops = []; 
      ims = []; 
      ip = Int64.zero;
      message = None;
      profile = Array.make 16 no_insn;
      is_target = true;
      plot = {
          count = 0; iptr = 0;
          disasm = "";
          events = []; result = ""; 
          first_cycle = 0; last_cycle = 16
      };
      regs = Array.make 16 Int64.zero; 
      mem = Memory.create () 
    } in
  machine

let add_event state code time =
  if state.show then begin
    let line = state.plot in
    line.events <- line.events @ [Event(time, code)];
    while time > line.last_cycle do line.last_cycle <- 16 + line.last_cycle done
  end

let add_result line res = line.result <- Printf.sprintf "%-50s" res

let line_indent = "                                                                                                                "
let line_background = Bytes.of_string "|                |                |                |                |                |"
let line_separator = "|----------------|----------------|----------------|----------------|----------------|"
let background_length = 80

let print_plotline state with_perf =
  let line = state.plot in
  if with_perf then begin
    if (line.count mod 16) = 0 then begin
      if (line.count mod 32) = 0 then begin
        let next_first_cycle = ref line.first_cycle in
        let first_cycle = match line.events with
          | Event(time,_) :: _ -> time
          | _ -> line.first_cycle
        in
        while !next_first_cycle <= first_cycle - 16 do next_first_cycle := 16 + !next_first_cycle done;
        if !next_first_cycle <> line.first_cycle then begin
          Printf.printf "\n%s                  %s\n" line_indent line_separator;
          line.first_cycle <- !next_first_cycle;
        end
      end;
      Printf.printf "\n%s  %6d / %6d %s" line_indent line.count line.first_cycle line_separator;
    end
  end;
  line.count <- 1 + line.count;

  let s = Printf.sprintf "%08X : " (Int64.to_int state.ip) in
  if with_perf then begin
    let put_char time char = begin
      let disp = time - line.first_cycle in
      let bars = 1 + disp / 16 in
      let pos = disp + bars in
      if disp < background_length then Bytes.set line_background pos char
    end in
    let put_event ev = match ev with Event(time,code) -> put_char time code in
    let zap_event ev = match ev with Event(time,_) -> put_char time ' ' in
    List.iter put_event line.events;
    let total = String.concat "" [s; state.info.encoding; state.info.disasm; line.result; Bytes.unsafe_to_string line_background] in
    Printf.printf "\n%s" total;
    List.iter zap_event line.events
  end else begin
    let total = String.concat "" [s; state.info.encoding; state.info.disasm; line.result] in
    Printf.printf "\n%s" total;
  end

let set_show state = state.show <- true

let set_tracefile state channel = state.tracefile <- Some channel

let set_args state arglist =
  let wrt_ptr = ref (Int64.of_int 0x20000000) in
  Memory.write_quad state.mem !wrt_ptr (Int64.of_int (List.length arglist));
  let wrt_arg arg = begin
    wrt_ptr := Int64.add !wrt_ptr (Int64.of_int 8);
    Memory.write_quad state.mem !wrt_ptr arg
  end in
  List.iter wrt_arg arglist

exception Unknown_digit of char

let hex_to_int c =
  match c with
  | '0' -> 0
  | '1' -> 1
  | '2' -> 2
  | '3' -> 3
  | '4' -> 4
  | '5' -> 5
  | '6' -> 6
  | '7' -> 7
  | '8' -> 8
  | '9' -> 9
  | 'A' -> 10
  | 'B' -> 11
  | 'C' -> 12
  | 'D' -> 13
  | 'E' -> 14
  | 'F' -> 15
  | 'a' -> 10
  | 'b' -> 11
  | 'c' -> 12
  | 'd' -> 13
  | 'e' -> 14
  | 'f' -> 15
  | _  -> 0



let init (hex : (int * string) list) : state = 
  let s = create () in
  let write_line (addr,b) = begin
    for entry = 0 to ((String.length b) / 2) - 1 do
      let digit = hex_to_int b.[entry * 2] * 16 + hex_to_int b.[entry * 2 + 1] in
      Memory.write_byte s.mem (Int64.of_int (addr + entry)) digit;
    done
  end
  in
  List.iter write_line hex;
  s

let next_ip state = state.ip <- Int64.succ state.ip

let _fetch state =
  let v = Memory.read_byte state.mem state.ip in
  next_ip state;
  v

let fetch state =
  let byte = _fetch state in
  if state.show then state.ops <- state.ops @ [byte];
  byte

let fetch_first state =
  let first_byte = _fetch state in
  if state.show then begin
    state.plot.iptr <- ((Int64.to_int state.ip) - 1);
    state.ops <- [first_byte];
    state.ims <- [];
    state.plot.events <- []
  end;
  first_byte

let fetch_imm state =
  let a = _fetch state in
  let b = _fetch state in
  let c = _fetch state in
  let d = _fetch state in
  let imm =(((((d lsl 8) + c) lsl 8) + b) lsl 8) + a in
  if state.show then state.ims <- state.ims @ [imm];
  imm

exception UnknownInstructionAt of int
exception UnimplementedCondition of int
exception UnknownPort of int

let split_byte byte = (byte lsr 4, byte land 0x0F)

let comp a b = Int64.compare a b

let eval_condition cond b a =
  (* Printf.printf "{ %d %x %x }" cond (Int64.to_int a) (Int64.to_int b); *)
  let open Ast in
  match cond with
  | E -> a = b
  | NE -> a <> b
  | L -> a < b
  | LE -> a <= b
  | G -> a > b
  | GE -> a >= b
  | A -> begin (* unsigned above  (a > b) *)
      if a < Int64.zero && b >= Int64.zero then true
      else if a >= Int64.zero && b < Int64.zero then false
      else a > b
    end
  | AE -> begin (* unsigned above or equal (a >= b) *)
      if a < Int64.zero && b >= Int64.zero then true
      else if a >= Int64.zero && b < Int64.zero then false
      else a >= b
    end
  | B -> begin (* unsigned below  (a < b) *)
      if a < Int64.zero && b >= Int64.zero then false
      else if a >= Int64.zero && b < Int64.zero then true
      else a < b
    end
  | BE -> begin (* unsigned below or equal (a <= b) *)
      if a < Int64.zero && b >= Int64.zero then false
      else if a >= Int64.zero && b < Int64.zero then true
      else a <= b
    end

let log_ip state =
  match state.tracefile with
  | Some(channel) -> Printf.fprintf channel "P %x %Lx\n" 0 state.ip
  | None -> ()

let wr_reg state reg value =
  if state.show then begin
      add_result state.plot (Printf.sprintf "%s <- 0x%Lx" (Printer.reg_name reg) value);
    end;
  begin
    match state.tracefile with
    | Some(channel) -> Printf.fprintf channel "R %x %Lx\n" reg value
    | None -> ()
  end;
  state.regs.(reg) <- value

let int64_two = Int64.of_int(2)

let is_io_area addr = (Int64.shift_right addr 28) = Int64.one
let is_argv_area addr = (Int64.shift_right addr 28) = int64_two

let perform_output port value = 
  if port = 2 then Printf.printf "%016Lx " value
  else raise (UnknownPort port)

let perform_input port =
  if port = 0 then Int64.of_int (read_int ())
  else if port = 1 then Random.int64 Int64.max_int
  else raise (UnknownPort port)

let rd_mem state (addr : Int64.t) =
  if is_io_area addr then
    let port = (Int64.to_int addr) land 0x0ff in
    let value = perform_input port in
    begin
      match state.tracefile with
      | Some(channel) -> Printf.fprintf channel "I %Lx %Lx\n" addr value
      | None -> ()
    end;
    value
  else if is_argv_area addr then
    let value = Memory.read_quad state.mem addr in
    begin
      match state.tracefile with
      | Some(channel) -> Printf.fprintf channel "I %Lx %Lx\n" addr value
      | None -> ()
    end;
    value
  else
    Memory.read_quad state.mem addr

let wr_mem state addr value =
  if is_io_area addr then begin
    let port = (Int64.to_int addr) land 0x0ff in
    if state.show then begin
      add_result state.plot (Printf.sprintf "Output <- %Lx" value)
    end;
    perform_output port value;
    match state.tracefile with
    | Some(channel) -> Printf.fprintf channel "O %Lx %Lx\n" addr value
    | None -> ()
  end else begin
    if state.show then begin
      add_result state.plot (Printf.sprintf "Memory[ 0x%Lx ] <- 0x%Lx" addr value)
    end;
    begin
      match state.tracefile with
      | Some(channel) -> Printf.fprintf channel "M %Lx %Lx\n" addr value
      | None -> ()
    end;
    Memory.write_quad state.mem addr value
  end

let set_ip state ip =
  if state.show then Printf.printf "Starting execution from address 0x%X\n" ip;
  state.ip <- Int64.of_int ip

let disas_imm imm = 
  let i : Int32.t = Int32.of_int imm in
  if i < Int32.zero then Int32.to_string i
  else Int32.to_string i





let disas_inst state =
  if state.show then begin
    state.plot.iptr <- Int64.to_int state.ip;
    state.ops <- [];
    state.ims <- [];
    state.plot.events <- []
  end;
  let tmp_ip = state.ip in
  let fetch_next _ = fetch state in
  let decoded = Codec.decode fetch_next in
  let disasm = Printf.sprintf "%-40s" (Printer.print_insn decoded) in
  let size = Int64.to_int state.ip - Int64.to_int tmp_ip in
  state.ip <- tmp_ip;
  let map_ops op = Printf.sprintf "%02X " op in
  let map_imm imm = Printf.sprintf "%08X " imm in
  let numlist = List.flatten [(List.map map_ops state.ops); (List.map map_imm state.ims)] in
  let numstring = String.concat "" numlist in
  let len_nums = String.length numstring in
  let void = String.make (50 - len_nums) ' ' in
  let encoding = String.concat "" [numstring; void] in
  encoding, decoded, disasm, size









let model_fetch_decode perf state =
  let start = Resource.acquire perf.fetch_start 0 in
  let start = Resource.acquire perf.fetch_decode_q start in
  let got_inst = Cache.cache_read perf.i state.ip start in
  let rob_entry = if perf.ooo then
    Resource.acquire perf.rob (got_inst + perf.dec_lat)
  else
    Resource.acquire perf.rob (Resource.acquire perf.alu (got_inst + perf.dec_lat)) 
  in
  Resource.use perf.fetch_start start (start + 1);
  Resource.use perf.fetch_decode_q start rob_entry;
  add_event state 'F' start;
  add_event state 'D' got_inst;
  if perf.ooo then add_event state 'Q' (rob_entry - 3);
  rob_entry

let model_decode_stall perf state f t_ino t_ooo = Resource.use perf.rob f t_ooo

let model_return perf state rs =
  let rob_entry = model_fetch_decode perf state in
  let ready = max perf.reg_ready.(rs) rob_entry in
  let exec_start = Resource.acquire perf.branch ready in
  let time_retire = Resource.acquire perf.retire (exec_start + 2) in
  let addr = state.regs.(rs) in
  let predicted = Predictors.predict_return perf.rp (Int64.to_int addr) in
  if predicted then
    Resource.use_all perf.fetch_start (Resource.get_earliest perf.fetch_start + 1)
  else begin
    Resource.use_all perf.fetch_start (exec_start + 1);
    state.info.exe_latency <- state.info.exe_latency + 1; (* wrong *)
  end;
  Resource.use perf.branch exec_start (exec_start + 1);
  Resource.use perf.retire time_retire (time_retire + 1);
  model_decode_stall perf state rob_entry exec_start time_retire;
  if perf.ooo then add_event state 's' (exec_start - 2);
  if perf.dec_lat > 2 then add_event state 'r' (exec_start - 1);
  add_event state 'B' exec_start;
  if perf.ooo then add_event state 'C' time_retire

let model_call perf state rd addr =
  let rob_entry = model_fetch_decode perf state in
  let time_retire = Resource.acquire perf.retire (rob_entry + 2) in
  Predictors.note_call perf.rp (Int64.to_int addr);
  Resource.use_all perf.fetch_start (Resource.get_earliest perf.fetch_start + 1);
  Resource.use perf.retire time_retire (time_retire + 1);
  model_decode_stall perf state rob_entry rob_entry time_retire;
  (* A call is resolved during decode, but still must write its return address *)
  add_event state 'w' (rob_entry + 1);
  if perf.ooo then add_event state 'C' time_retire;
  perf.reg_ready.(rd) <- rob_entry + 1

let model_jmp perf state =
  let rob_entry = model_fetch_decode perf state in
  let exec_start = Resource.acquire perf.branch rob_entry in
  let time_retire = Resource.acquire perf.retire (exec_start + 2) in
  Resource.use_all perf.fetch_start (Resource.get_earliest perf.fetch_start + 1);
  Resource.use perf.branch exec_start (exec_start + 1);
  Resource.use perf.retire time_retire (time_retire + 1);
  model_decode_stall perf state rob_entry exec_start time_retire;
  add_event state 'B' exec_start;
  if perf.ooo then add_event state 'C' time_retire

let model_nop perf state =
  let rob_entry = model_fetch_decode perf state in
  let exec_start = Resource.acquire perf.alu rob_entry in
  let time_retire = Resource.acquire perf.retire (exec_start + 2) in
  model_decode_stall perf state rob_entry exec_start time_retire;
  Resource.use perf.alu exec_start (exec_start + 1);
  Resource.use perf.retire time_retire (time_retire + 1)

let model_cond_branch perf state from_ip to_ip taken ops_ready =
  let rob_entry = model_fetch_decode perf state in
  let ready = max rob_entry ops_ready in
  let exec_start = Resource.acquire perf.branch ready in
  let exec_done = exec_start + 1 in
  let time_retire = Resource.acquire perf.retire (exec_done + 1) in
  let predicted = Predictors.predict_and_train perf.bp from_ip to_ip taken in
  if not predicted then
    Resource.use_all perf.fetch_start exec_done
  else if taken then
    Resource.use_all perf.fetch_start (Resource.get_earliest perf.fetch_start + 1);
  Resource.use perf.branch exec_start (exec_done);
  Resource.use perf.retire time_retire (time_retire + 1);
  model_decode_stall perf state rob_entry exec_start time_retire;
  if perf.ooo then add_event state 's' (exec_start - 2);
  if perf.dec_lat > 2 then add_event state 'r' (exec_start - 1);
  add_event state 'B' exec_start;
  if perf.ooo then add_event state 'C' time_retire

let model_compute perf state rd ops_ready latency =
  let rob_entry = model_fetch_decode perf state in
  let ready = max rob_entry ops_ready in
  let exec_start = Resource.acquire perf.alu ready in
  let exec_done = exec_start + latency in
  let time_retire = Resource.acquire perf.retire (exec_done + 1) in
  Resource.use perf.alu exec_start (exec_done);
  Resource.use perf.retire time_retire (time_retire + 1);
  perf.reg_ready.(rd) <- exec_done;
  model_decode_stall perf state rob_entry exec_start time_retire;
  if perf.ooo then add_event state 's' (exec_start - 2);
  if perf.dec_lat > 2 then add_event state 'r' (exec_start - 1);
  add_event state 'X' exec_start;
  add_event state 'w' exec_done;
  state.info.exe_latency <- state.info.exe_latency + latency;
  if perf.ooo then add_event state 'C' time_retire

let model_mov_imm perf state rd = model_compute perf state rd 0 1
let model_leaq perf state rd ops_ready = model_compute perf state rd ops_ready 1
let model_mov_reg perf state rd rs = model_compute perf state rd (perf.reg_ready.(rs)) 1
let model_alu_imm perf state rd = model_compute perf state rd (perf.reg_ready.(rd)) 1
let model_mul_imm perf state rd = model_compute perf state rd (perf.reg_ready.(rd)) 3
let model_alu_reg perf state rd rs = model_compute perf state rd (max perf.reg_ready.(rd) perf.reg_ready.(rs)) 1
let model_mul_reg perf state rd rs = model_compute perf state rd (max perf.reg_ready.(rd) perf.reg_ready.(rs)) 3

let model_store perf state rd rs addr =
  let ops_ready = perf.reg_ready.(rs) in
  let rob_entry = model_fetch_decode perf state in
  let ready = max rob_entry ops_ready in
  let agen_start = Resource.acquire perf.agen ready in
  let agen_done = agen_start + 1 in
  let store_data_ready = max agen_done perf.reg_ready.(rd) in
  let access_start = Resource.acquire perf.dcache store_data_ready in
  let _ = Cache.cache_write perf.d addr access_start in
  let access_done = access_start + 1 in
  let time_retire = Resource.acquire perf.retire (access_done + 1) in
  Resource.use perf.agen agen_start agen_done;
  Resource.use perf.dcache access_start (access_start + 1);
  Resource.use perf.retire time_retire (time_retire + 1);
  model_decode_stall perf state rob_entry agen_start time_retire;
  if perf.ooo then add_event state 's' (agen_start - 2);
  if perf.dec_lat > 2 then add_event state 'r' (agen_start - 1);
  add_event state 'A' agen_start;
  add_event state 'V' access_start;
  if perf.ooo then add_event state 'C' time_retire

let model_load perf state rd rs addr =
  let ops_ready = perf.reg_ready.(rs) in
  let rob_entry = model_fetch_decode perf state in
  let ready = max rob_entry ops_ready in
  let agen_start = Resource.acquire perf.agen ready in
  let agen_done = agen_start + 1 in
  let access_start = Resource.acquire perf.dcache agen_done in
  let data_ready = Cache.cache_read perf.d addr access_start in
  let time_retire = Resource.acquire perf.retire (data_ready + 1) in
  Resource.use perf.agen agen_start agen_done;
  Resource.use perf.dcache access_start (access_start + 1);
  Resource.use perf.retire time_retire (time_retire + 1);
  model_decode_stall perf state rob_entry agen_start time_retire;
  if perf.ooo then add_event state 's' (agen_start - 2);
  if perf.dec_lat > 2 then add_event state 'r' (agen_start - 1);
  add_event state 'A' agen_start;
  add_event state 'L' access_start;
  add_event state 'w' data_ready;
  state.info.exe_latency <- state.info.exe_latency + (data_ready - agen_start);
  if perf.ooo then add_event state 'C' time_retire;
  perf.reg_ready.(rd) <- data_ready

let model_load_imm perf state rd rs = model_load perf state rd perf.reg_ready.(rs)







let unsigned_mul a b =
  if a < Int64.zero then
    if b < Int64.zero then
      Int64.mul (Int64.neg a) (Int64.neg b)
    else
      Int64.neg (Int64.mul (Int64.neg a) b)
  else 
    if b < Int64.zero then
      Int64.neg (Int64.mul a (Int64.neg b))
    else
      Int64.mul a b


let get_insn_info state =
  let ip = Int64.to_int state.ip in
  let len = Array.length state.profile in
  if (ip >= len) then begin
    let new_len = 2 * (max len ip) in
    let new_profile : insn_info array = Array.make new_len no_insn in
    for i = 0 to (len - 1) do new_profile.(i) <- state.profile.(i) done;
    state.profile <- new_profile
  end;
  if state.profile.(ip) == no_insn then begin
    let enc,dec,dis,sz = disas_inst state in
    state.profile.(ip) <- { decoded = Some(dec); encoding = enc; disasm = dis; size = sz; 
                            count = 0; exe_latency = 0; time_change = 0; is_target = false };
  end;
  state.profile.(ip)


let run_op op rd_val rs_val =
  let open Ast in
  match op with
  | ADD -> Int64.add rd_val rs_val
  | SUB -> Int64.sub rd_val rs_val
  | AND -> Int64.logand rd_val rs_val
  | OR  -> Int64.logor rd_val rs_val
  | XOR -> Int64.logxor rd_val rs_val
  | MUL -> unsigned_mul rd_val rs_val
  | SAR -> Int64.shift_right rd_val (Int64.to_int rs_val)
  | SAL -> Int64.shift_left rd_val (Int64.to_int rs_val)
  | SHR -> Int64.shift_right_logical rd_val (Int64.to_int rs_val)
  | IMUL ->Int64.mul rd_val rs_val
  | _ -> raise Codec.UnknownInstruction


let run_inst perf state =
  log_ip state;
  let i = get_insn_info state in
  state.info <- i;
  i.count <- 1 + i.count;
  if state.is_target then begin (* mark insn if it was the target of a jmp/call *)
    state.is_target <- false;
    state.info.is_target <- true;
  end;
  state.ip <- Int64.add state.ip (Int64.of_int i.size);  (* FIXME: add and use field next_ip *)
  match i.decoded with
  | Some(Ctl1(RET,Reg(rs))) -> begin
      let ret_addr = state.regs.(rs) in (* return instruction *)
      (* model_return perf state rs; *)
      state.ip <- ret_addr;
      if state.show then add_result state.plot "";
      if ret_addr <= Int64.zero then begin
          log_ip state; (* final IP value should be added to trace *)
          state.running <- false;
          if state.show then
            state.message <- Some (Printf.sprintf "\nTerminating. Return to address %Lx\n" ret_addr)
        end
    end
  | Some(Alu2(op,Reg(rs),Reg(rd))) when op <> LEA -> begin
      let rd_val = state.regs.(rd) in
      let rs_val = state.regs.(rs) in
      let result = run_op op rd_val rs_val in
      wr_reg state rd result
    end
  | Some(Alu2(op,Imm(Value(imm)),Reg(rd))) when op <> LEA -> begin
      let rd_val = state.regs.(rd) in
      let result = run_op op rd_val imm in
      wr_reg state rd result
    end
  | Some(Alu2(LEA,am,Reg(rd))) -> begin
      let result = match am with
      | EaS(rs) -> state.regs.(rs)
      | EaZ(rz, shamt) -> Int64.shift_left state.regs.(rz) shamt
      | EaZS(rs, rz, shamt) -> Int64.add state.regs.(rs) (Int64.shift_left state.regs.(rz) shamt)
      | EaD(Value(imm)) -> imm
      | EaDS(Value(imm), rs) -> Int64.add imm state.regs.(rs)
      | EaDZ(Value(imm), rz, shamt) -> Int64.add imm (Int64.shift_left state.regs.(rz) shamt)
      | EaDZS(Value(imm), rs, rz, shamt) -> 
             Int64.add (Int64.add imm state.regs.(rs)) (Int64.shift_left state.regs.(rz) shamt)
      | _ -> raise Codec.UnknownInstruction
      in 
      wr_reg state rd result
    end
  | Some(Move2(MOV,from,Reg(rd))) -> begin
      let result = match from with
      | Reg(rs) -> state.regs.(rs)
      | EaS(rs) -> rd_mem state state.regs.(rs)
      | Imm(Value(imm)) -> imm
      | EaDS(Value(imm),rs) -> rd_mem state (Int64.add imm state.regs.(rs))
      | _ -> raise Codec.UnknownInstruction
      in
      wr_reg state rd result
    end
  | Some(Move2(MOV,Reg(rd),EaS(rs))) -> wr_mem state state.regs.(rs) state.regs.(rd)
  | Some(Move2(MOV,Reg(rd),EaDS(Value(imm), rs))) -> wr_mem state (Int64.add imm state.regs.(rs)) state.regs.(rd)
  | Some(Ctl2(CALL,EaD(Value(imm)),Reg(rd))) -> begin
      wr_reg state rd state.ip;
      state.is_target <- true;
      state.ip <- imm
    end
  | Some(Ctl1(JMP,EaD(Value(imm)))) -> begin
      if state.show then add_result state.plot "";
      state.is_target <- true;
      state.ip <- imm
    end
  | Some(Ctl3(CBcc(cond),opspec,Reg(rd),EaD(Value(imm)))) -> begin
      if state.show then add_result state.plot "";
      let op = match opspec with
      | Reg(rs) -> state.regs.(rs)
      | Imm(Value(imm)) -> imm
      | _ -> raise Codec.UnknownInstruction
      in
      let taken = eval_condition cond state.regs.(rd) op in
      if taken then begin
        state.ip <- imm;
        state.is_target <- true
      end
    end
  | _ -> raise Codec.UnknownInstruction




(*
  | 4,_ | 5,_ | 6,_ | 7,_ -> begin (* instructions with 2 bytes + 1 immediate *)
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      match hi,lo with
      | 4,0xE -> begin
          wr_reg state rd state.ip; 
          model_call perf state rd state.ip;
          state.is_target <- true;
          state.ip <- qimm (* call *)
        end
      | 4,0xF -> begin
          model_jmp perf state;
          if state.show then add_result state.plot "";
          state.is_target <- true;
          state.ip <- qimm (* jmp *)
        end
      | 4,_ -> begin
          let taken = eval_condition lo state.regs.(rd) state.regs.(rs) in
          let ops_ready = max perf.reg_ready.(rd) perf.reg_ready.(rs) in
          model_cond_branch perf state (Int64.to_int state.ip) imm taken ops_ready;
          if state.show then add_result state.plot (if taken then "<T>" else "<NT>");
          if taken then begin
            state.ip <- qimm;
            state.is_target <- true;
          end
        end
*)
(*
  | 8,_ | 9,_ | 10,_ | 11,_ -> begin // leaq
      let has_third_byte = hi = 9 || hi = 11 in
      let has_imm = hi = 10 || hi = 11 in
      let (rz,sh) = if has_third_byte then split_byte (fetch state) else 0,0 in
      let qimm = if has_imm then imm_to_qimm (fetch_imm state) else Int64.zero in
      let hasS = lo land 1 = 1 in
      let hasZ = lo land 2 = 2 in
      let hasD = lo land 4 = 4 in
      let ea = Int64.add (if hasS then state.regs.(rs) else Int64.zero)
               (Int64.add (if hasZ then Int64.shift_left state.regs.(rz) sh else Int64.zero)
               (if hasD then qimm else Int64.zero))
      in
      let ops_ready = max (if hasS then perf.reg_ready.(rs) else 0) (if hasZ then perf.reg_ready.(rz) else 0) in
      model_leaq perf state rd ops_ready;
      wr_reg state rd ea
    end
*)

(*
  | 1,0 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.add state.regs.(rd) state.regs.(rs))
  | 1,1 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.sub state.regs.(rd) state.regs.(rs))
  | 1,2 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.logand state.regs.(rd) state.regs.(rs))
  | 1,3 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.logor state.regs.(rd) state.regs.(rs))
  | 1,4 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.logxor state.regs.(rd) state.regs.(rs))
  | 1,5 -> model_mul_reg perf state rd rs; wr_reg state rd (unsigned_mul state.regs.(rd) state.regs.(rs))
  | 1,6 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.shift_right state.regs.(rd) (Int64.to_int state.regs.(rs)))
  | 1,7 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.shift_left state.regs.(rd) (Int64.to_int state.regs.(rs)))
  | 1,8 -> model_alu_reg perf state rd rs; wr_reg state rd (Int64.shift_right_logical state.regs.(rd) (Int64.to_int state.regs.(rs)))
  | 1,9 -> model_mul_reg perf state rd rs; wr_reg state rd (Int64.mul state.regs.(rd) state.regs.(rs))
*)

(*
  | 2,1 -> model_mov_reg perf state rd rs; wr_reg state rd state.regs.(rs)
  | 3,1 -> begin
      model_load perf state rd rs state.regs.(rs);
      wr_reg state rd (rd_mem state state.regs.(rs))
    end
  | 3,9 -> begin
      model_store perf state rd rs state.regs.(rs);
      wr_mem state state.regs.(rs) state.regs.(rd)
    end
*)
(*
      | 5,0 -> model_alu_imm perf state rd; wr_reg state rd (Int64.add state.regs.(rd) qimm)
      | 5,1 -> model_alu_imm perf state rd; wr_reg state rd (Int64.sub state.regs.(rd) qimm)
      | 5,2 -> model_alu_imm perf state rd; wr_reg state rd (Int64.logand state.regs.(rd) qimm)
      | 5,3 -> model_alu_imm perf state rd; wr_reg state rd (Int64.logor state.regs.(rd) qimm)
      | 5,4 -> model_alu_imm perf state rd; wr_reg state rd (Int64.logxor state.regs.(rd) qimm)
      | 5,5 -> model_mul_imm perf state rd; wr_reg state rd (unsigned_mul state.regs.(rd) qimm)
      | 5,6 -> model_alu_imm perf state rd; wr_reg state rd (Int64.shift_right state.regs.(rd) imm)
      | 5,7 -> model_alu_imm perf state rd; wr_reg state rd (Int64.shift_left state.regs.(rd) imm)
      | 5,8 -> model_alu_imm perf state rd; wr_reg state rd (Int64.shift_right_logical state.regs.(rd) imm)
      | 5,9 -> model_mul_imm perf state rd; wr_reg state rd (Int64.mul state.regs.(rd) qimm)
*)
(*
      | 6,4 -> model_mov_imm perf state rd; wr_reg state rd qimm
      | 7,5 -> begin
          let a = Int64.add qimm state.regs.(rs) in
          model_load perf state rd rs a;
          wr_reg state rd (rd_mem state a)
        end
      | 7,0xD -> begin
          let a = Int64.add qimm state.regs.(rs) in
          model_store perf state rd rs a;
          wr_mem state a state.regs.(rd)
        end
      | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
*)
(*
    end
  | 15,_ -> begin (* cbcc with both imm and target *)
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      let a_imm = fetch_imm state in
      let q_a_imm = imm_to_qimm a_imm in
      let taken = eval_condition lo state.regs.(rd) qimm in
      model_cond_branch perf state (Int64.to_int state.ip) imm taken perf.reg_ready.(rd);
      if state.show then add_result state.plot (if taken then "<T>" else "<NT>");
      if (taken) then begin
        state.ip <- q_a_imm;
        state.is_target <- true;
      end
    end
  | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
*)


let run perf state =
  state.running <- true;
  while state.running && state.ip >= Int64.zero do
    run_inst perf state;
    if state.show then begin
      print_plotline state perf.perf_model;
      match state.message with
      | Some(s) -> Printf.printf "%s" s
      | None -> ()
    end
  done;
  begin
    match state.tracefile with
    | Some(channel) -> close_out channel
    | None -> ()
  end;
  state.tracefile <- None;
  if state.show then Printf.printf "\nSimulation terminated\n";
  if perf.profile then begin
    Printf.printf "\n\nExecution profile:\n";
    let max = (Array.length state.profile) - 1 in
    for i = 0 to max do
      if state.profile.(i) <> no_insn then begin
        let insn = state.profile.(i) in
        let d = match insn.decoded with None -> "err" | Some(e) -> Printer.print_insn e in
        let with_lat = insn.exe_latency <> 0 in
        if insn.is_target then Printf.printf "%x:\n" i;
        if with_lat then begin
          let avg_lat = (float_of_int insn.exe_latency) /. (float_of_int insn.count) in
          Printf.printf "%6X : %8d  %6.2f  %-40s\n" i insn.count avg_lat d
        end else begin
          Printf.printf "%6X : %8d          %-40s\n" i insn.count d
        end
      end
    done
  end
