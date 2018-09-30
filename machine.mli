type state

type perf = { 
    bp : Predictors.predictor;
    rp : Predictors.predictor;
    l2 : Cache.cache;
    i : Cache.cache;
    d : Cache.cache;
  }


val create : unit -> state
val set_show : state -> unit
val set_tracefile : state -> out_channel -> unit
val init : (string * string) list -> state
val set_ip : state -> int -> unit
val run : perf -> state -> unit
