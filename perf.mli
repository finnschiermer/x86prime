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

val model_perf : Machine.state -> perf -> unit

val run : perf -> Machine.state -> unit

