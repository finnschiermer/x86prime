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
  let earliest = ref (max earliest resource.window_start) in
  let found = ref false in
  let timespan = Array.length resource.window in
  if resource.inorder then
    while resource.window_start < !earliest do
      move_window resource
    done;
  while !found do
    while !earliest >= resource.window_start + timespan do
      move_window resource
    done;
    let index = !earliest mod timespan in
    if resource.window.(index) > 0 then
      found := true
    else
      earliest := 1 + !earliest;
  done;
  !earliest

let use resource start finished =
  let timespan = Array.length resource.window in
  while finished >= resource.window_start + timespan do
    move_window resource
  done;
  if resource.inorder then
    while resource.window_start < start do
      move_window resource
    done;
  if start < resource.window_start then raise (Too_short_timespan resource.name);
  for t = start to finished - 1 do
    let index = t mod timespan in
    if resource.window.(index) > 0 then
      resource.window.(index) <- resource.window.(index) - 1;
  done
