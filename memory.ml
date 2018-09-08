exception OutOfSimulatedMemory
exception Argghhh

type t = (Int64.t, (Int64.t array)) Hashtbl.t

let create () : t = Hashtbl.create 16

let txl_addr (addr : Int64.t) =
  let word_addr = Int64.shift_right_logical addr 3 in
  let byte_offset = Int64.sub addr (Int64.shift_left word_addr 3) in
  let page_addr = Int64.shift_right_logical word_addr 8 in
  let page_offset = Int64.sub word_addr (Int64.shift_left page_addr 8) in
  (page_addr, page_offset, byte_offset)

type page = Int64.t array

let get_page mem page_addr =
  match Hashtbl.find_opt mem page_addr with
  | Some(page) -> page
  | None -> if (Hashtbl.length mem > 100) then
              raise OutOfSimulatedMemory
            else
              let page = (Array.make 256 Int64.zero) in
              Hashtbl.add mem page_addr page;
              page

let ext_quad page offset = page.(Int64.to_int offset)

let ins_quad page offset quad = page.(Int64.to_int offset) <- quad

let ins_byte offset quad value =
  let mask = Int64.lognot (Int64.shift_left (Int64.of_int 0x0FF) (8 * Int64.to_int offset)) in
  let aligned_value = Int64.shift_left (Int64.of_int value) (8 * Int64.to_int offset) in
  let new_value = Int64.logor aligned_value (Int64.logand quad mask) in
  new_value

let ext_byte offset quad =
  let aligned = Int64.shift_right_logical quad (8 * Int64.to_int offset) in
  Int64.to_int (Int64.logand aligned (Int64.of_int 0x0FF))

let read_byte mem addr =
  let page_addr, quad_offset, byte_offset = txl_addr addr in
  let page = get_page mem page_addr in
  let quad = ext_quad page quad_offset in
  let byte = ext_byte byte_offset quad in
  byte

let write_byte mem addr value =
  let page_addr, quad_offset, byte_offset = txl_addr addr in
  let page = get_page mem page_addr in
  let quad = ext_quad page quad_offset in
  let new_quad = ins_byte byte_offset quad value in
  ins_quad page quad_offset new_quad

let write_quad mem addr value =
  let page_addr, quad_offset, byte_offset = txl_addr addr in
  let page = get_page mem page_addr in
  ins_quad page quad_offset value

let read_quad mem addr =
  let page_addr, quad_offset, byte_offset = txl_addr addr in
  let page = get_page mem page_addr in
  let quad = ext_quad page quad_offset in
  quad
