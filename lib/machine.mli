type state

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


val create : unit -> state
val set_show : state -> unit
val set_limit : state -> int -> unit
val set_tracefile : state -> out_channel -> unit
val set_args : state -> int64 list -> unit
val init : (int * string) list -> state
val set_ip : state -> int -> unit
val run : perf -> state -> unit
val runloop : perf -> state -> unit
val is_running : state -> bool
val cleanup : perf -> state -> unit