
type memory = (Int64.t, (Int64.t array)) Hashtbl.t
type registers = Int64.t array

type state = {
    mutable ip : Int64.t;
    regs : registers;
    mem : Memory.t;
  }

let create () = 
  let machine = { ip = Int64.zero; regs = Array.make 16 Int64.zero; mem = Memory.create () } in
  machine.regs.(15) <- Int64.of_int (- 1);
  machine

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

let set_ip state ip =
  state.ip <- Int64.of_int ip

let next_ip state = state.ip <- Int64.succ state.ip

let fetch state =
  let first_byte = Memory.read_byte state.mem state.ip in
  next_ip state;
  first_byte

let fetch_imm state =
  let a = fetch state in
  let b = fetch state in
  let c = fetch state in
  let d = fetch state in
  (((((d lsl 8) + c) lsl 8) + b) lsl 8) + a

let imm_to_qimm imm =
  if (imm lsr 31) == 0 then
    Int64.of_int imm
  else (* negative *)
    let hi = Int64.shift_left (Int64.of_int 0xFFFF) 32 in
    let lo = Int64.of_int imm in
    Int64.logor hi lo

exception UnknownInstructionAt of int
exception UnimplementedCondition of int

let split_byte byte = (byte lsr 4, byte land 0x0F)

let eval_condition cond b a =
  Printf.printf " { %d %d %d } " cond (Int64.to_int a) (Int64.to_int b);
  match cond with
  | 0 -> (Int64.compare a b) = 0
  | 1 -> (Int64.compare a b) <> 0
  | 4 -> (Int64.compare a b) < 0
  | 5 -> (Int64.compare a b) <= 0
  | 6 -> (Int64.compare a b) > 0
  | 7 -> (Int64.compare a b) >= 0
  | _ -> raise (UnimplementedCondition cond)

let run_inst state =
  let first_byte = fetch state in
  Printf.printf "\n%x : %02x " ((Int64.to_int state.ip) - 1) first_byte;
  let (hi,lo) = split_byte first_byte in
  match hi,lo with
  | 0,0 -> state.ip <- state.regs.(15) (* return instruction *)
  | 6,0xE | 6,0xF -> begin
      let imm = fetch_imm state in
      let qimm = imm_to_qimm imm in
      Printf.printf "%08x " imm;
      if lo = 0xE then begin
        state.regs.(15) <- state.ip; state.ip <- qimm  (* call *)
      end else 
        state.ip <- qimm (* jmp *)
    end
  | _ -> begin (* all other insns needs one more byte before any imm *)
      let second_byte = fetch state in
      let (rd,rs) = split_byte second_byte in
      Printf.printf "%02x " second_byte;
      match hi,lo with
      | 1,0 -> state.regs.(rd) <- Int64.add state.regs.(rd) state.regs.(rs)
      | 1,1 -> state.regs.(rd) <- Int64.sub state.regs.(rd) state.regs.(rs)
      | 1,2 -> state.regs.(rd) <- Int64.logand state.regs.(rd) state.regs.(rs)
      | 1,3 -> state.regs.(rd) <- Int64.logor state.regs.(rd) state.regs.(rs)
      | 1,4 -> state.regs.(rd) <- Int64.logxor state.regs.(rd) state.regs.(rs)
      | 1,5 -> state.regs.(rd) <- Int64.mul state.regs.(rd) state.regs.(rs)
      | 2,0 -> state.regs.(rd) <- state.regs.(rs)
      | 2,1 -> state.regs.(rd) <- Memory.read_quad state.mem state.regs.(rs)
      | 2,2 -> Memory.write_quad state.mem state.regs.(rs) state.regs.(rd)
      | 3,0 -> state.regs.(rd) <- state.regs.(rs)
      | 3,_ -> begin
          let third_byte = fetch state in
          Printf.printf "%02x " third_byte;
          let (rz,sh) = split_byte third_byte in
          match lo with
          | 1 -> state.regs.(rd) <- Int64.add state.regs.(rs) state.regs.(rz)
          | 2 -> state.regs.(rd) <- Int64.add state.regs.(rs) (Int64.shift_left state.regs.(rz) sh)
          | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
        end
      | 4,_ | 5,_ | 7,0 | 7,1 -> begin
          let imm = fetch_imm state in
          let qimm = imm_to_qimm imm in
          Printf.printf "%08x " imm;
          match hi,lo with
          | 4,0 -> state.regs.(rd) <- Int64.add state.regs.(rd) qimm
          | 4,1 -> state.regs.(rd) <- Int64.sub state.regs.(rd) qimm
          | 4,2 -> state.regs.(rd) <- Int64.logand state.regs.(rd) qimm
          | 4,3 -> state.regs.(rd) <- Int64.logor state.regs.(rd) qimm
          | 4,4 -> state.regs.(rd) <- Int64.logxor state.regs.(rd) qimm
          | 4,5 -> state.regs.(rd) <- Int64.mul state.regs.(rd) qimm
          | 5,0 -> state.regs.(rd) <- Memory.read_quad state.mem qimm
          | 5,1 -> state.regs.(rd) <- Memory.read_quad state.mem (Int64.add qimm state.regs.(rs))
          | 5,2 -> Memory.write_quad state.mem (Int64.add qimm state.regs.(rs)) state.regs.(rd)
          | 7,0 -> state.regs.(rd) <- qimm
          | 7,1 -> state.regs.(rd) <- Int64.add qimm state.regs.(rs)
          | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
        end
      | 6,_ -> begin
          let imm = fetch_imm state in
          let qimm = imm_to_qimm imm in
          Printf.printf "%08x " imm;
          let taken = eval_condition lo state.regs.(rd) state.regs.(rs) in
               if taken then state.ip <- qimm
        end
      | 7,2 | 7,3 -> begin
          let third_byte = fetch state in
          Printf.printf "%02x " third_byte;
          let (rz,sh) = split_byte third_byte in
          let imm = fetch_imm state in
          let qimm = imm_to_qimm imm in
          Printf.printf "%08x " imm;
          match hi,lo with
          | 7,2 -> state.regs.(rd) <- Int64.add qimm (Int64.add state.regs.(rs) state.regs.(rz))
          | 7,3 -> state.regs.(rd) <- Int64.add qimm (Int64.add state.regs.(rs) (Int64.shift_left state.regs.(rz) sh))
          | _ -> ()
        end
      | 8,0 -> begin
          let imm = fetch_imm state in
          let qimm = imm_to_qimm imm in
          Printf.printf "%08x " imm;
          let a_imm = fetch_imm state in
          let q_a_imm = imm_to_qimm a_imm in
          Printf.printf "%08x " a_imm;
          let taken = eval_condition rs state.regs.(rd) qimm in
          if (taken) then state.ip <- q_a_imm
        end
      | _ -> raise (UnknownInstructionAt (Int64.to_int state.ip))
    end


let run state =
  while (Int64.compare state.ip Int64.zero) > 0 do
    run_inst state
  done
