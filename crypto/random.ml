open Common
open Types
open Modules

exception InvalidRandomState

let refresh_bh h s x =
  let n = String.length !s in
  let tmp = h ("extract" ^ x) in
  if n = String.length tmp then begin
    for i = 0 to n-1 do
      tmp.[i] <- char_of_int ((int_of_char tmp.[i]) lxor (int_of_char !s.[i]))
    done;
    s := h ("G_prime" ^ tmp)
  end else raise InvalidRandomState

let next_bh h s () =
  let rnd_bytes = h ("G_first" ^ !s) in
  s := h ("G_secnd" ^ !s);
  rnd_bytes

type state = {
  seed : string -> unit;
  refresh : string -> unit;
  next : unit -> string;
}

let make_bh_prng h seed =
  let state = ref (h seed) in
  { seed = (fun x -> state := (h x));
    refresh = refresh_bh h state;
    next = next_bh h state }


let random_char s =
  let tmp = s.next () in
  tmp.[0]

let random_string s len =
  let rec aux accu remaining =
    let tmp = s.next () in
    if String.length tmp >= remaining
    then String.concat "" ((String.sub tmp 0 remaining)::accu)
    else aux (tmp::accu) (remaining - (String.length tmp))
  in aux [] len

let random_int s max =
  let rec n_bytes n =
    if n = 0 then 0
    else 1 + (n_bytes (n lsr 8))
  in

  if max < 0 then raise (Common.WrongParameter "random_int expect a positive max");
  let len = n_bytes (max - 1) in

  let rec aux () =
    let tmp = ref 0
    and rnd = random_string s len in
    for i = 0 to (len - 1) do
      tmp := (!tmp lsl 8) lor (int_of_char rnd.[i])
    done;
    if !tmp < max then !tmp else aux ()
  in
  aux ()


module RandomLib = struct
  let name = "random"
  let state = make_bh_prng Crypto.sha256sum ""
  let params = []

  let functions = [
    "seed", NativeFun (one_value_fun (fun s -> state.seed (eval_as_string s); V_Unit));
    "refresh", NativeFun (one_value_fun (fun s -> state.refresh (eval_as_string s); V_Unit));
    "int", NativeFun (one_value_fun (fun max -> V_Int (random_int state (eval_as_int max))));
    "string", NativeFun (one_value_fun (fun len -> V_BinaryString (random_string state (eval_as_int len))))
  ]
end

module RandomModule = MakeLibraryModule (RandomLib)
let _ = add_library_module ((module RandomModule : Module))

