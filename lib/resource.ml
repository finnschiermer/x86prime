exception Too_short_timespan of string

type resource = {
    num_instances : int;
    inorder : bool;
    mutable window_start : int;
    window : int array;
    name : string;
  }

let create name inorder num_instances max_timespan =
  {
    num_instances = num_instances;
    inorder = inorder;
    window_start = 0;
    window = Array.make max_timespan num_instances;
    name = name;
  }

let move_window resource =
  let idx = resource.window_start mod (Array.length resource.window) in
  resource.window.(idx) <- resource.num_instances;
  resource.window_start <- 1 + resource.window_start

let use_all resource time_finished =
  while resource.window_start < time_finished do
    move_window resource
  done

let get_earliest resource = resource.window_start

let acquire resource earliest =
  let first_free = ref (max earliest resource.window_start) in
  let found = ref false in
  let timespan = Array.length resource.window in
  if resource.inorder then
    while resource.window_start < !first_free do
      move_window resource
    done;
  while not !found do
    while !first_free >= resource.window_start + timespan do
      move_window resource
    done;
    let index = !first_free mod timespan in
    if resource.window.(index) > 0 then
      found := true
    else
      first_free := 1 + !first_free;
  done;
(*  Printf.printf "ACQ %s %d -> %d\n" resource.name earliest !first_free; *)
  !first_free

let use resource start finished =
(*  Printf.printf "USE %s %d %d (%d)\n" resource.name start finished (finished - start); *)
  let timespan = Array.length resource.window in
  while finished >= resource.window_start + timespan do
    move_window resource
  done;
  if resource.inorder then
    while resource.window_start < start do
      move_window resource
    done;
  let start = max start resource.window_start in
(*  if start < resource.window_start then 
    raise (Too_short_timespan (Printf.sprintf "%s:%d - %d" resource.name start finished)); *)
  for t = start to finished - 1 do
    let index = t mod timespan in
    if resource.window.(index) > 0 then
      resource.window.(index) <- resource.window.(index) - 1;
  done
