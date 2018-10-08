type cache_block = {
    mutable tag : int option;
    block : int array; (* timestamps *)
  }

type cache_set = cache_block array

type cache = {
    index_bits : int;
    block_bits : int;
    latency : int;
    ways : cache_set array;
    next_layer : memory_layer;
    mutable num_reads : int;
    mutable num_writes : int;
    mutable num_miss : int;
  }

and memory_layer =
  | MainMemory of int
  | Cache of cache

let cache_create index_bits block_bits assoc latency next_layer =

  let block_size = 1 lsl (block_bits - 3) in
  let way_size = 1 lsl index_bits in
  let cache_block_create i = {
      tag = None;
      block = Array.make block_size max_int;
    }
  in
  let cache_way_create i = Array.init assoc cache_block_create in
  {
    index_bits = index_bits;
    block_bits = block_bits;
    latency = latency;
    ways = Array.init way_size cache_way_create;
    next_layer = next_layer;
    num_reads = 0;
    num_writes = 0;
    num_miss = 0;
  }

let cache_get_stats cache = (cache.num_reads, cache.num_writes, cache.num_miss)

let rec cache_access cache address time is_write =
  let quad_address = Int64.to_int (Int64.shift_right_logical address 3) in
  let tag_shift = cache.index_bits + cache.block_bits - 3 in
  let index_shift = cache.block_bits - 3 in
  let tag = quad_address lsr tag_shift in
  let quad_offset = quad_address - (tag lsl tag_shift) in
  let index = quad_offset lsr index_shift in
  let quad_offset_in_block = quad_offset - (index lsl index_shift) in
  let found = ref None in
  let assoc_end = Array.length cache.ways.(index) in
  let assoc = ref 0 in
  if is_write then
    cache.num_writes <- 1 + cache.num_writes
  else
    cache.num_reads <- 1 + cache.num_reads;
  (* search for cache hit *)
  while !found = None && !assoc < assoc_end do
    let entry = cache.ways.(index).(!assoc) in
    begin match entry.tag with
    | Some(e) -> if e = tag then found := Some(!assoc,entry)
    | None -> ()
    end;
    assoc := 1 + !assoc
  done;
  match !found with 
  | Some(idx,entry) -> begin (* Hit, MRU update *)
      for i = idx - 1 downto 0 do
        cache.ways.(index).(i + 1) <- cache.ways.(index).(i)
      done;
      if is_write then entry.block.(quad_offset_in_block) <- time;
      cache.ways.(index).(0) <- entry;
      cache.latency + (max time entry.block.(quad_offset_in_block))
    end
  | None -> begin (* Miss, Discard LRU entry, add new one first in MRU order *)
      cache.num_miss <- 1 + cache.num_miss;
      for i = assoc_end - 2 downto 0 do
        cache.ways.(index).(i + 1) <- cache.ways.(index).(i)
      done;
      let block_size = 1 lsl (cache.block_bits - 3) in
      let block_arrival = match cache.next_layer with
        | Cache(c) -> cache_access c address time is_write
        | MainMemory(delay) -> time + delay
      in
      let new_entry = { 
          tag = Some(tag);
          block = Array.make block_size block_arrival;
        }
      in
      if is_write then new_entry.block.(quad_offset_in_block) <- time;
      cache.ways.(index).(0) <- new_entry;
      cache.latency + (max time new_entry.block.(quad_offset_in_block))
    end

let cache_read cache address time = 
    cache_access cache address time false

let cache_write cache address time = 
    cache_access cache address time true

