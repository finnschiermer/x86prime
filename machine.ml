
type memory = (Int64.t, (Int64.t array)) Hashtbl.t
type registers = Int64.t array

type state = {
    mutable show : bool;
    mutable running : bool;
    mutable p_pos : int;
    mutable tracefile : out_channel option;
    mutable ip : Int64.t;
    regs : registers;
    mem : Memory.t;
  }

let create () = 
  let machine = { 
      show = false; 
      running = false;
      p_pos = 0; 
      tracefile = None; 
      ip = Int64.zero; 
      regs = Array.make 16 Int64.zero; 
      mem = Memory.create () 
    } in
  machine

let set_show state = state.show <- true

let set_tracefile state channel = state.tracefile <- Some channel

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



let init (hex : (string * string) list) : state = 
  let s = create () in
  let write_line (a,b) =
    Scanf.sscanf a "%x" (fun addr ->
        for entry = 0 to ((String.length b) / 2) - 1 do
          let digit = hex_to_int b.[entry * 2] * 16 + hex_to_int b.[entry * 2 + 1] in
          Memory.write_byte s.mem (Int64.of_int (addr + entry)) digit;
        done)
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
  if state.show then Printf.printf "%02x " byte;
  state.p_pos <- 3 + state.p_pos;
  byte

let fetch_first state =
  let first_byte = _fetch state in
  if state.show then Printf.printf "\n%08x : %02x " ((Int64.to_int state.ip) - 1) first_byte;
  state.p_pos <- 3;
  first_byte

let fetch_imm state =
  let a = _fetch state in
  let b = _fetch state in
  let c = _fetch state in
  let d = _fetch state in
  let imm =(((((d lsl 8) + c) lsl 8) + b) lsl 8) + a in
  if state.show then Printf.printf "%08x " imm;
  state.p_pos <- 9 + state.p_pos;
  imm

let imm_to_qimm imm =
  if (imm lsr 31) == 0 then
    Int64.of_int imm
  else (* negative *)
    let hi = Int64.shift_left (Int64.of_int 0xFFFFFFFF) 32 in
    let lo = Int64.of_int imm in
    Int64.logor hi lo

exception UnknownInstructionAt of int
exception UnimplementedCondition of int

let split_byte byte = (byte lsr 4, byte land 0x0F)

let eval_condition cond b a =
  (* Printf.printf "{ %d %x %x }" cond (Int64.to_int a) (Int64.to_int b); *)
  match cond with
  | 0 -> (Int64.compare a b) = 0
  | 1 -> (Int64.compare a b) <> 0
  | 4 -> (Int64.compare a b) < 0
  | 5 -> (Int64.compare a b) <= 0
  | 6 -> (Int64.compare a b) > 0
  | 7 -> (Int64.compare a b) >= 0
  | _ -> raise (UnimplementedCondition cond)

let align_output state =
  while state.p_pos < 30 do
    Printf.printf " ";
    state.p_pos <- 1 + state.p_pos
  done

let reg_name reg =
  match reg with
  | 0 -> "%rax"
  | 1 -> "%rbx"
  | 2 -> "%rcx"
  | 3 -> "%rdx"
  | 4 -> "%rbp"
  | 5 -> "%rsi"
  | 6 -> "%rdi"
  | 7 -> "%rsp"
  | _ -> Printf.sprintf "%%r%2d" reg

let wr_ip state value = begin
  match state.tracefile with
    | Some(channel) -> Printf.fprintf channel "I %x %Lx\n" 0 value
    | None -> ()
  end;
  state.ip <- value


let wr_reg state reg value =
  if state.show then begin
      align_output state;
      Printf.printf "%s <- %Lx" (reg_name reg) value;
    end;
  begin
    match state.tracefile with
    | Some(channel) -> Printf.fprintf channel "R %x %Lx\n" reg value
    | None -> ()
  end;
  state.regs.(reg) <- value

let wr_mem state addr value =
  if state.show then begin
      align_output state;
      Printf.printf "Memory[ %Lx ] <- %Lx" addr value
    end;
  begin
    match state.tracefile with
    | Some(channel) -> Printf.fprintf channel "M %Lx %Lx\n" addr value
    | None -> ()
  end;
  Memory.write_quad state.mem addr value

let set_ip state ip =
  if state.show then Printf.printf "Starting execution from address %X\n" ip;
  wr_ip state (Int64.of_int ip)


let run_inst state =
  let first_byte = fetch_first state in
  let (hi,lo) = split_byte first_byte in
  let second_byte = fetch state in
  let (rd,rs) = split_byte second_byte in
  match hi,lo with
  | 0,0 -> begin
      let ret_addr = state.regs.(15) in (* return instruction *)
      if ret_addr > Int64.zero then
        wr_ip state ret_addr
      else begin
        state.running <- false;
        if state.show then Printf.printf "\nTerminating. Return to address %Lx\n" ret_addr
        end
    end
  | 1,0 -> wr_reg state rd (Int64.add state.regs.(rd) state.regs.(rs))
  | 1,1 -> wr_reg state rd (Int64.sub state.regs.(rd) state.regs.(rs))
  | 1,2 -> wr_reg state rd (Int64.logand state.regs.(rd) state.regs.(rs))
  | 1,3 -> wr_reg state rd (Int64.logor state.regs.(rd) state.regs.(rs))
  | 1,4 -> wr_reg state rd (Int64.logxor state.regs.(rd) state.regs.(rs))
  | 1,5 -> wr_reg state rd (Int64.mul state.regs.(rd) state.regs.(rs))
  | 2,0 -> wr_reg state rd state.regs.(rs)
  | 2,1 -> wr_reg state rd (Memory.read_quad state.mem state.regs.(rs))
  | 2,2 -> wr_mem state state.regs.(rs) state.regs.(rd)
  | 3,_ -> begin (* instructions with 3 bytes *)
      let third_byte = fetch state in
      let (rz,sh) = split_byte third_byte in
      match lo with
      | 0 -> wr_reg state rd (state.regs.(rs))
      | 1 -> wr_reg state rd (Int64.add state.regs.(rs) (Int64.shift_left state.regs.(rz) sh))
      | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
    end
  | 4,_ | 5,_ | 6,_ -> begin (* instructions with 2 bytes + 1 immediate *)
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      match hi,lo with
      | 4,0 -> wr_reg state rd (Int64.add state.regs.(rd) qimm)
      | 4,1 -> wr_reg state rd (Int64.sub state.regs.(rd) qimm)
      | 4,2 -> wr_reg state rd (Int64.logand state.regs.(rd) qimm)
      | 4,3 -> wr_reg state rd (Int64.logor state.regs.(rd) qimm)
      | 4,4 -> wr_reg state rd (Int64.logxor state.regs.(rd) qimm)
      | 4,5 -> wr_reg state rd (Int64.mul state.regs.(rd) qimm)
      | 5,0 -> wr_reg state rd qimm
      | 5,1 -> wr_reg state rd (Memory.read_quad state.mem (Int64.add qimm state.regs.(rs)))
      | 5,2 -> wr_mem state (Int64.add qimm state.regs.(rs)) state.regs.(rd)
      | 6,0xE -> wr_reg state 15 state.ip; wr_ip state qimm (* call *)
      | 6,0xF -> wr_ip state qimm (* jmp *)
      | 6,_ -> let taken = eval_condition lo state.regs.(rd) state.regs.(rs) in
               if taken then wr_ip state qimm
      | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
    end
  | 7,0 | 7,1 | 7,2 -> begin (* instructions with 3 bytes + 1 immediate *)
      let third_byte = fetch state in
      let (rz,sh) = split_byte third_byte in
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      match hi,lo with
      | 7,0 -> wr_reg state rd qimm
      | 7,1 -> wr_reg state rd (Int64.add qimm state.regs.(rs))
      | 7,2 -> wr_reg state rd (Int64.add qimm (Int64.add state.regs.(rs) (Int64.shift_left state.regs.(rz) sh)))
      | _ -> ()
    end
  | 8,_ -> begin (* instructions with 2 bytes + 2 immediates *)
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      let a_imm = fetch_imm state in
      let q_a_imm = imm_to_qimm a_imm in
      let taken = eval_condition lo state.regs.(rd) qimm in
      if (taken) then wr_ip state q_a_imm
    end
  | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))


let run state =
  state.running <- true;
  while state.running && state.ip >= Int64.zero do
    run_inst state
  done;
  begin
    match state.tracefile with
    | Some(channel) -> close_out channel
    | None -> ()
  end;
  state.tracefile <- None;
  if state.show then Printf.printf "\nSimulation terminated\n"
