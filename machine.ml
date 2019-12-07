
type memory = (Int64.t, (Int64.t array)) Hashtbl.t
type registers = Int64.t array
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
    mutable next_ip : Int64.t;
    mutable message : string option;
    mutable profile : insn_info array;
    mutable is_target : bool;
    mutable data_address : Int64.t;
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
      next_ip = Int64.zero;
      message = None;
      profile = Array.make 16 no_insn;
      is_target = true;
      data_address = Int64.zero;
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

let line_indent = "                                                                                                                 "
let line_background = Bytes.of_string "|                |                |                |                |                |"
let line_separator = "|----------------|----------------|----------------|----------------|----------------|"
let background_length = 80

let print_plotline state =
  let s = Printf.sprintf "%08X : " (Int64.to_int state.ip) in
  let total = String.concat "" [s; state.info.encoding; state.info.disasm; state.plot.result] in
  Printf.printf "\n%s" total

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
  let void = String.make (30 - len_nums) ' ' in
  let encoding = String.concat "" [numstring; void] in
  encoding, decoded, disasm, size




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


let run_inst state =
  log_ip state;
  let i = get_insn_info state in
  state.info <- i;
  i.count <- 1 + i.count;
  if state.is_target then begin (* mark insn if it was the target of a jmp/call *)
    state.is_target <- false;
    state.info.is_target <- true;
  end;
  state.next_ip <- Int64.add state.ip (Int64.of_int i.size);
  match i.decoded with
  | Some(Ctl1(RET,Reg(rs))) -> begin
      let ret_addr = state.regs.(rs) in (* return instruction *)
      state.next_ip <- ret_addr;
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
      | EaS(rs) -> begin
          state.data_address <- state.regs.(rs);
          rd_mem state state.data_address
        end
      | Imm(Value(imm)) -> imm
      | EaDS(Value(imm),rs) -> begin
          state.data_address <- Int64.add imm state.regs.(rs);
          rd_mem state state.data_address
        end
      | _ -> raise Codec.UnknownInstruction
      in
      wr_reg state rd result
    end
  | Some(Move2(MOV,Reg(rd),EaS(rs))) -> begin
      state.data_address <- state.regs.(rs);
      wr_mem state state.data_address state.regs.(rd)
    end
  | Some(Move2(MOV,Reg(rd),EaDS(Value(imm), rs))) -> begin
      state.data_address <- Int64.add imm state.regs.(rs);
      wr_mem state state.data_address state.regs.(rd)
    end
  | Some(Ctl2(CALL,EaD(Value(imm)),Reg(rd))) -> begin
      wr_reg state rd state.next_ip;
      state.is_target <- true;
      state.next_ip <- imm
    end
  | Some(Ctl1(JMP,EaD(Value(imm)))) -> begin
      if state.show then add_result state.plot "";
      state.is_target <- true;
      state.next_ip <- imm
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
        state.next_ip <- imm;
        state.is_target <- true
      end
    end
  | _ -> raise Codec.UnknownInstruction




let run state =
  state.running <- true;
  while state.running && state.ip >= Int64.zero do
    run_inst state;
    if state.show then begin
      print_plotline state;
      match state.message with
      | Some(s) -> Printf.printf "%s" s
      | None -> ()
    end;
    state.ip <- state.next_ip
  done;
  begin
    match state.tracefile with
    | Some(channel) -> close_out channel
    | None -> ()
  end;
  state.tracefile <- None;
  if state.show then Printf.printf "\nSimulation terminated\n";


