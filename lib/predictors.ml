exception PredictorMismatch

type return_predictor_state = {
    mutable stack_p : int;
    stack : int array;
  }

type predictor_machine = SNT | WNT | WT | ST

type dynamic_predictor_state = {
    mutable history : int;
    predictors : predictor_machine array;
  }

type predictor_kind = 
  | PredTaken | PredNotTaken | PredBTFNT | PredOracle
  | PredReturn of return_predictor_state
  | PredLocal of dynamic_predictor_state
  | PredGShare of dynamic_predictor_state

type predictor = {
    mutable num_predictions : int;
    mutable num_miss : int;
    mutable kind : predictor_kind;
  }

let create_return_predictor stacksize : predictor =
  let r = { stack_p = 0; stack = Array.make stacksize 0} in
  let p = { num_predictions = 0; num_miss = 0; kind = PredReturn(r) } in
  p

let create_taken_predictor () : predictor =
  { num_predictions = 0; num_miss = 0; kind = PredTaken }

let create_not_taken_predictor () : predictor =
  { num_predictions = 0; num_miss = 0; kind = PredNotTaken }

let create_btfnt_predictor () : predictor =
  { num_predictions = 0; num_miss = 0; kind = PredBTFNT }

let create_oracle_predictor () : predictor =
  { num_predictions = 0; num_miss = 0; kind = PredOracle }

let create_local_predictor num_index_bits : predictor =
  let num_state_machines = 1 lsl num_index_bits in
  let r = {history = 0; predictors = Array.make num_state_machines WT; } in
  { num_predictions = 0; num_miss = 0; kind = PredLocal(r) }

let create_gshare_predictor num_index_bits : predictor =
  let num_state_machines = 1 lsl num_index_bits in
  let r = {history = 0; predictors = Array.make num_state_machines WT; } in
  { num_predictions = 0; num_miss = 0; kind = PredGShare(r) }

let note_call predictor target =
  match predictor.kind with
  | PredReturn(pred_state) -> begin
      let sp = pred_state.stack_p + 1 in
      let max = Array.length pred_state.stack in
      let sp = if sp = max then 0 else sp in
      pred_state.stack.(sp) <- target;
      pred_state.stack_p <- sp;
    end
  | _ -> raise PredictorMismatch

let predict_return predictor target : bool =
  predictor.num_predictions <- 1 + predictor.num_predictions;
  match predictor.kind with
  | PredReturn(pred_state) -> begin
      let sp = pred_state.stack_p in
      let max = Array.length pred_state.stack in
      let prediction = pred_state.stack.(sp) in
      let sp = if sp = 0 then max - 1 else sp - 1 in
      let hit = target = prediction in
      if not hit then predictor.num_miss <- 1 + predictor.num_miss;
      pred_state.stack_p <- sp;
      hit
    end
  | _ -> raise PredictorMismatch

let make_prediction state = 
  match state with
  | SNT | WNT -> false
  | ST | WT -> true

let next_predictor_state state taken =
  match taken,state with
  | false, SNT -> SNT
  | false, WNT -> SNT
  | false, WT -> WNT
  | false, ST -> WT
  | true, SNT -> WNT
  | true, WNT -> WT
  | true, WT -> ST
  | true, ST -> ST

let predict_and_train predictor pc target taken : bool =
  predictor.num_predictions <- 1 + predictor.num_predictions;
  let hit = match predictor.kind with
  | PredTaken -> taken
  | PredNotTaken -> not taken
  | PredBTFNT -> begin
      let prediction = target < pc in
      prediction = taken
    end
  | PredOracle -> true
  | PredLocal(pred_state) -> begin
      let mask = (Array.length pred_state.predictors) - 1 in
      let index = pc land mask in
      let predictor_state = pred_state.predictors.(index) in
      let prediction = make_prediction predictor_state in
      pred_state.predictors.(index) <- next_predictor_state predictor_state taken;
      prediction = taken
    end
  | PredGShare(pred_state) -> begin
      let mask = (Array.length pred_state.predictors) - 1 in
      let index = (pred_state.history lxor pc) land mask in
      let predictor_state = pred_state.predictors.(index) in
      let prediction = make_prediction predictor_state in
      pred_state.predictors.(index) <- next_predictor_state predictor_state taken;
      if taken then pred_state.history <- pred_state.history lor (mask + 1);
      pred_state.history <- pred_state.history lsr 1;
      prediction = taken
    end
  | _ -> raise PredictorMismatch
  in
  if not hit then predictor.num_miss <- 1 + predictor.num_miss;
  hit

let predictor_get_results predictor = predictor.num_predictions, predictor.num_miss
