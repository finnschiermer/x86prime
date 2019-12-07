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

open Machine


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
  let predicted = Predictors.predict_and_train perf.bp (Int64.to_int from_ip) (Int64.to_int to_ip) taken in
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





let model_perf state perf =
  state.plot.events <- [];
  let i = state.info in
  match i.decoded with
  | Some(Ctl1(RET,Reg(rs))) -> begin
      model_return perf state rs;
    end
  | Some(Alu2(op,Reg(rs),Reg(rd))) when op <> LEA -> begin
      match op with
      | MUL | IMUL -> model_mul_reg perf state rd rs
      | _ -> model_alu_reg perf state rd rs
    end
  | Some(Alu2(op,Imm(Value(imm)),Reg(rd))) when op <> LEA -> begin
      match op with
      | MUL | IMUL -> model_mul_imm perf state rd
      | _ -> model_alu_imm perf state rd
    end
  | Some(Alu2(LEA,am,Reg(rd))) -> begin
      let ops_ready = match am with
      | EaS(rs) -> perf.reg_ready.(rs)
      | EaZ(rz, shamt) -> perf.reg_ready.(rz)
      | EaZS(rs, rz, shamt) -> max perf.reg_ready.(rs) perf.reg_ready.(rz)
      | EaD(Value(imm)) -> 0
      | EaDS(Value(imm), rs) -> perf.reg_ready.(rs)
      | EaDZ(Value(imm), rz, shamt) -> perf.reg_ready.(rz)
      | EaDZS(Value(imm), rs, rz, shamt) -> max perf.reg_ready.(rs) perf.reg_ready.(rz)
      | _ -> raise Codec.UnknownInstruction
      in
      model_leaq perf state rd ops_ready
    end
  | Some(Move2(MOV,from,Reg(rd))) -> begin
      match from with
      | Reg(rs) -> model_mov_reg perf state rd rs
      | EaS(rs) -> model_load perf state rd rs state.data_address
      | Imm(Value(imm)) -> model_mov_imm perf state rd
      | EaDS(Value(imm),rs) -> model_load perf state rd rs state.data_address
      | _ -> raise Codec.UnknownInstruction
    end
  | Some(Move2(MOV,Reg(rd),EaS(rs))) -> model_store perf state rd rs state.data_address
  | Some(Move2(MOV,Reg(rd),EaDS(Value(imm), rs))) -> model_store perf state rd rs state.data_address
  | Some(Ctl2(CALL,EaD(Value(imm)),Reg(rd))) -> model_call perf state rd state.regs.(rd)
  | Some(Ctl1(JMP,EaD(Value(imm)))) -> model_jmp perf state
  | Some(Ctl3(CBcc(cond),opspec,Reg(rd),EaD(Value(imm)))) -> begin
      let ops_ready = match opspec with
      | Reg(rs) -> max perf.reg_ready.(rd) perf.reg_ready.(rs)
      | Imm(_) -> perf.reg_ready.(rd)
      | _ -> raise Codec.UnknownInstruction
      in
      model_cond_branch perf state state.ip state.next_ip state.is_target ops_ready
    end
  | _ -> raise Codec.UnknownInstruction


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

let run perf state =
  state.running <- true;
  while state.running && state.ip >= Int64.zero do
    Machine.run_inst state;
    model_perf state perf;
    if state.show then begin
      print_plotline state perf.perf_model;
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
