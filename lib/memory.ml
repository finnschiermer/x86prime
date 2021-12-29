exception OutOfSimulatedMemory
exception Argghhh

type t = (int, bytes) Hashtbl.t

let create () : t = Hashtbl.create 16

let txl_addr (addr : Int64.t) =
  let page_addr = Int64.shift_right_logical addr 10 in
  let byte_offset = Int64.sub addr (Int64.shift_left page_addr 10) in
  (Int64.to_int page_addr, Int64.to_int byte_offset)

type page = bytes

let get_page mem page_addr =
  match Hashtbl.find_opt mem page_addr with
  | Some(page) -> page
  | None -> if (Hashtbl.length mem > 100000) then
              raise OutOfSimulatedMemory
            else
              let page = (Bytes.make 1024 (Char.chr 0)) in
              Hashtbl.add mem page_addr page;
              page

let read_byte mem addr =
  let page_addr, byte_offset = txl_addr addr in
  let page = get_page mem page_addr in
  Char.code (Bytes.get page byte_offset)

let write_byte mem addr value =
  let page_addr, byte_offset = txl_addr addr in
  let page = get_page mem page_addr in
  Bytes.set page byte_offset (Char.chr (value land 0xff))


let write_quad mem addr value =
  write_byte mem (Int64.add addr (Int64.of_int 7)) (Int64.to_int (Int64.shift_right_logical value 56));
  write_byte mem (Int64.add addr (Int64.of_int 6)) (Int64.to_int (Int64.shift_right_logical value 48));
  write_byte mem (Int64.add addr (Int64.of_int 5)) (Int64.to_int (Int64.shift_right_logical value 40));
  write_byte mem (Int64.add addr (Int64.of_int 4)) (Int64.to_int (Int64.shift_right_logical value 32));
  write_byte mem (Int64.add addr (Int64.of_int 3)) (Int64.to_int (Int64.shift_right_logical value 24));
  write_byte mem (Int64.add addr (Int64.of_int 2)) (Int64.to_int (Int64.shift_right_logical value 16));
  write_byte mem (Int64.add addr (Int64.of_int 1)) (Int64.to_int (Int64.shift_right_logical value 8));
  write_byte mem (Int64.add addr (Int64.of_int 0)) (Int64.to_int value)

let read_quad mem addr =
  let v7 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 7))) in
  let v6 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 6))) in
  let v5 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 5))) in
  let v4 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 4))) in
  let v3 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 3))) in
  let v2 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 2))) in
  let v1 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 1))) in
  let v0 = Int64.of_int (read_byte mem (Int64.add addr (Int64.of_int 0))) in
  Int64.logor
    (Int64.logor
      (Int64.logor (Int64.shift_left v7 56) (Int64.shift_left v6 48))
      (Int64.logor (Int64.shift_left v5 40) (Int64.shift_left v4 32)))
    (Int64.logor
      (Int64.logor (Int64.shift_left v3 24) (Int64.shift_left v2 16))
      (Int64.logor (Int64.shift_left v1 8) v0))
