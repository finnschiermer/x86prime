
type memory = (Int64.t, (Int64.t array)) Hashtbl.t
type registers = Int64.t array

type state = {
    mutable show : bool;
    mutable running : bool;
    mutable p_pos : int;
    mutable disas : Ast.line option;
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
      disas = None;
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

let comp a b = Int64.compare a b

let eval_condition cond b a =
  (* Printf.printf "{ %d %x %x }" cond (Int64.to_int a) (Int64.to_int b); *)
  match cond with
  | 0 -> a = b
  | 1 -> a <> b
  | 4 -> a < b
  | 5 -> a <= b
  | 6 -> a > b
  | 7 -> a >= b
  | _ -> raise (UnimplementedCondition cond)

let disas_cond cond =
  let open Ast in
  match cond with
  | 0 -> E
  | 1 -> NE
  | 4 -> L
  | 5 -> LE
  | 6 -> G
  | 7 -> GE
  | _ -> raise (UnimplementedCondition cond)

let align_output state =
  while state.p_pos < 30 do
    Printf.printf " ";
    state.p_pos <- 1 + state.p_pos
  done;
  match state.disas with
  | Some(d) -> Printf.printf "%-40s" (Printer.print_insn d)
  | None -> ()

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
  | _ -> Printf.sprintf "%%r%-2d" reg

let log_ip state =
  match state.tracefile with
  | Some(channel) -> Printf.fprintf channel "I %x %Lx\n" 0 state.ip
  | None -> ()

let wr_reg state reg value =
  if state.show then begin
      align_output state;
      Printf.printf "%s <- 0x%Lx" (reg_name reg) value;
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
      Printf.printf "Memory[ 0x%Lx ] <- 0x%Lx" addr value
    end;
  begin
    match state.tracefile with
    | Some(channel) -> Printf.fprintf channel "M %Lx %Lx\n" addr value
    | None -> ()
  end;
  Memory.write_quad state.mem addr value

let set_ip state ip =
  if state.show then Printf.printf "Starting execution from address 0x%X\n" ip;
  state.ip <- Int64.of_int ip

let fetch_from_offs state offs =
  Memory.read_byte state.mem (Int64.add state.ip (Int64.of_int offs)) 

let fetch_imm_from_offs state offs =
  let a = fetch_from_offs state offs in
  let b = fetch_from_offs state (offs + 1) in
  let c = fetch_from_offs state (offs + 2) in
  let d = fetch_from_offs state (offs + 3) in
  let imm =(((((d lsl 8) + c) lsl 8) + b) lsl 8) + a in
  imm

let disas_reg r =
  match r with
  | 0 -> "%rax"
  | 1 -> "%rbx"
  | 2 -> "%rcx"
  | 3 -> "%rdx"
  | 4 -> "%rbp"
  | 5 -> "%rsi"
  | 6 -> "%rdi"
  | 7 -> "%rsp"
  | _ -> Printf.sprintf "%%r%d" r


let disas_sh sh =
  match sh with
  | 0 -> "1"
  | 1 -> "2"
  | 2 -> "4"
  | 3 -> "8"
  | _ -> "?"

let disas_imm imm = 
  let i : Int32.t = Int32.of_int imm in
  if i < Int32.zero then Int32.to_string i
  else Int32.to_string i

let disas_mem imm = Printf.sprintf "0x%x" imm

let disas_inst state =
  let first_byte = fetch_from_offs state 0 in
  let (hi,lo) = split_byte first_byte in
  let second_byte = fetch_from_offs state 1 in
  let (rd,rs) = split_byte second_byte in
  match hi,lo with
  | 0,0 -> Ast.Ctl1(RET,Reg(disas_reg rs));
  | 1,0 -> Ast.Alu2(ADD,Reg(disas_reg rs), Reg(disas_reg rd));
  | 1,1 -> Ast.Alu2(SUB,Reg(disas_reg rs), Reg(disas_reg rd));
  | 1,2 -> Ast.Alu2(AND,Reg(disas_reg rs), Reg(disas_reg rd));
  | 1,3 -> Ast.Alu2(OR,Reg(disas_reg rs), Reg(disas_reg rd));
  | 1,4 -> Ast.Alu2(XOR,Reg(disas_reg rs), Reg(disas_reg rd));
  | 1,5 -> Ast.Alu2(MUL,Reg(disas_reg rs), Reg(disas_reg rd));
  | 2,1 -> Ast.Move2(MOV,Reg(disas_reg rs), Reg(disas_reg rd));
  | 3,1 -> Ast.Move2(MOV,EaS(disas_reg rs), Reg(disas_reg rd));
  | 3,9 -> Ast.Move2(MOV,Reg(disas_reg rd), EaS(disas_reg rs));
  | 4,_ | 5,_ | 6,_ | 7,_ -> begin (* instructions with 2 bytes + 1 immediate *)
      let imm = fetch_imm_from_offs state 2 in
      match hi,lo with
      | 4,0xE -> Ast.Ctl2(CALL,EaD(disas_mem imm),Reg(disas_reg rd))
      | 4,0xF -> Ast.Ctl1(JMP,EaD(disas_mem imm))
      | 4,_ -> Ast.Ctl3(CBcc(disas_cond lo),Reg(disas_reg rd),Reg(disas_reg rs),EaD(disas_mem imm));
      | 5,0 -> Ast.Alu2(ADD,Imm(disas_imm imm),Reg(disas_reg rd))
      | 5,1 -> Ast.Alu2(SUB,Imm(disas_imm imm),Reg(disas_reg rd))
      | 5,2 -> Ast.Alu2(AND,Imm(disas_imm imm),Reg(disas_reg rd))
      | 5,3 -> Ast.Alu2(OR,Imm(disas_imm imm),Reg(disas_reg rd))
      | 5,4 -> Ast.Alu2(XOR,Imm(disas_imm imm),Reg(disas_reg rd))
      | 5,5 -> Ast.Alu2(MUL,Imm(disas_imm imm),Reg(disas_reg rd))
      | 6,4 -> Ast.Move2(MOV,Imm(disas_imm imm),Reg(disas_reg rd))
      | 7,5 -> Ast.Move2(MOV,EaDS(disas_imm imm,disas_reg rs),Reg(disas_reg rd))
      | 7,0xD ->Ast.Move2(MOV,Reg(disas_reg rd), EaDS(disas_imm imm,disas_reg rs))
      | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
    end
  | 8,_ | 9,_ | 10,_ | 11,_ -> begin (* leaq *)
      let has_third_byte = hi = 9 || hi = 11 in
      let has_imm = hi = 10 || hi = 11 in
      let imm_offs = if has_third_byte then 3 else 2 in
      let (rz,sh) = if has_third_byte then split_byte (fetch_from_offs state 2) else 0,0 in
      let imm = if has_imm then fetch_imm_from_offs state imm_offs else 0 in
      match lo with
      | 1 -> Ast.Alu2(LEA,EaS(disas_reg rs),Reg(disas_reg rd))
      | 2 -> Ast.Alu2(LEA,EaZ(disas_reg rz,disas_sh sh),Reg(disas_reg rd))
      | 3 -> Ast.Alu2(LEA,EaZS(disas_reg rs,disas_reg rz,disas_sh sh),Reg(disas_reg rd))
      | 4 -> Ast.Alu2(LEA,EaD(disas_mem imm),Reg(disas_reg rd))
      | 5 -> Ast.Alu2(LEA,EaDS(disas_imm imm, disas_reg rs),Reg(disas_reg rd))
      | 6 -> Ast.Alu2(LEA,EaDZ(disas_imm imm, disas_reg rz,disas_sh sh),Reg(disas_reg rd))
      | 7 -> Ast.Alu2(LEA,EaDZS(disas_imm imm, disas_reg rs,disas_reg rz,disas_sh sh),Reg(disas_reg rd))
      | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
    end
  | 15,_ -> begin (* cbcc with both imm and target *)
      let imm = fetch_imm_from_offs state 2 in
      let a_imm = fetch_imm_from_offs state 6 in
      Ast.Ctl3(CBcc(disas_cond lo),Imm(disas_imm imm),Reg(disas_reg rd),EaD(disas_mem a_imm))
    end
  | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))

let terminate_output state = if state.show then align_output state

let run_inst state =
  log_ip state;
  if state.show then state.disas <- Some(disas_inst state);
  let first_byte = fetch_first state in
  let (hi,lo) = split_byte first_byte in
  let second_byte = fetch state in
  let (rd,rs) = split_byte second_byte in
  match hi,lo with
  | 0,0 -> begin
      terminate_output state;
      let ret_addr = state.regs.(rs) in (* return instruction *)
      state.ip <- ret_addr;
      if ret_addr <= Int64.zero then begin
          log_ip state; (* final IP value should be added to trace *)
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
  | 2,1 -> wr_reg state rd state.regs.(rs)
  | 3,1 -> wr_reg state rd (Memory.read_quad state.mem state.regs.(rs))
  | 3,9 -> wr_mem state state.regs.(rs) state.regs.(rd)
  | 4,_ | 5,_ | 6,_ | 7,_ -> begin (* instructions with 2 bytes + 1 immediate *)
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      match hi,lo with
      | 4,0xE -> wr_reg state rd state.ip; state.ip <- qimm (* call *)
      | 4,0xF -> terminate_output state; state.ip <- qimm (* jmp *)
      | 4,_ -> terminate_output state;
               let taken = eval_condition lo state.regs.(rd) state.regs.(rs) in
               if taken then state.ip <- qimm
      | 5,0 -> wr_reg state rd (Int64.add state.regs.(rd) qimm)
      | 5,1 -> wr_reg state rd (Int64.sub state.regs.(rd) qimm)
      | 5,2 -> wr_reg state rd (Int64.logand state.regs.(rd) qimm)
      | 5,3 -> wr_reg state rd (Int64.logor state.regs.(rd) qimm)
      | 5,4 -> wr_reg state rd (Int64.logxor state.regs.(rd) qimm)
      | 5,5 -> wr_reg state rd (Int64.mul state.regs.(rd) qimm)
      | 6,4 -> wr_reg state rd qimm
      | 7,5 -> wr_reg state rd (Memory.read_quad state.mem (Int64.add qimm state.regs.(rs)))
      | 7,0xD -> wr_mem state (Int64.add qimm state.regs.(rs)) state.regs.(rd)
      | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
    end
  | 8,_ | 9,_ | 10,_ | 11,_ -> begin (* leaq *)
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
      wr_reg state rd ea
    end
  | 15,_ -> begin (* cbcc with both imm and target *)
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      let a_imm = fetch_imm state in
      let q_a_imm = imm_to_qimm a_imm in
      let taken = eval_condition lo state.regs.(rd) qimm in
      terminate_output state;
      if (taken) then state.ip <- q_a_imm
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
