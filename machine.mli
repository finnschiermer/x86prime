type state

type perf = { 
    bp : Predictors.predictor;
    rp : Predictors.predictor;
  }


val create : unit -> state
val set_show : state -> unit
val set_tracefile : state -> out_channel -> unit
val init : (string * string) list -> state
val set_ip : state -> int -> unit
val run : perf -> state -> unit
