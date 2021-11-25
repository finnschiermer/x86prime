
exception OutOfSimulatedMemory

type t

val create : unit -> t

val write_byte : t -> Int64.t -> int -> unit
val read_byte : t -> Int64.t -> int
val write_quad : t -> Int64.t -> int64 -> unit
val read_quad :  t -> Int64.t -> int64
