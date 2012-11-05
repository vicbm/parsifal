open Lwt
open Unix

open Parsifal
open TlsEnums
open Tls
open Getopt


let host = ref "www.google.com"
let port = ref 443

let options = [
  mkopt (Some 'h') "help" Usage "show this help";

  mkopt (Some 'H') "host" (StringVal host) "host to contact";
  mkopt (Some 'p') "port" (IntVal port) "port to probe";
]

let getopt_params = {
  default_progname = "sslproxy";
  options = options;
  postprocess_funs = [];
}



(* TODO: Handle exceptions in lwt code, and add timers *)


type tls_state = {
  name : string;
  mutable clear : bool;
}

let empty_state name =
  { name = name; clear = true }


let rec _really_write o s p l =
  Lwt_unix.write o s p l >>= fun n ->
  if l = n then
    Lwt.return ()
  else
    _really_write o s (p + n) (l - n)

let really_write o s = _really_write o s 0 (String.length s)


let write_record o record =
  let s = dump_tls_record record in
  really_write o s


let rec forward state i o =
  lwt_parse_tls_record None i >>= fun record ->
  print_string (print_tls_record ~name:state.name record);
  write_record o record >>= fun () ->
  try
    begin
      match record.content_type, state.clear with
      | CT_Handshake, true ->
	let hs_msg = parse_handshake_msg None (input_of_string "Handshake" (dump_record_content record.record_content)) in
	print_endline (print_handshake_msg ~indent:"  " ~name:"Handshake content" hs_msg)
      | CT_ChangeCipherSpec, true ->
	let hs_msg = parse_change_cipher_spec (input_of_string "CCS" (dump_record_content record.record_content)) in
	print_endline (print_change_cipher_spec ~indent:"  " ~name:"CCS content" hs_msg);
	state.clear <- false
      | CT_Alert, true ->
	let hs_msg = parse_tls_alert (input_of_string "Alert" (dump_record_content record.record_content)) in
	print_endline (print_tls_alert ~indent:"  " ~name:"Alert content" hs_msg)
      | _ -> print_newline ()
    end;
    forward state i o
  with e -> fail e


let catcher = function
  | ParsingException (e, StringInput i) ->
    Printf.printf "%s in %s\n" (print_parsing_exception e)
      (print_string_input i); flush Pervasives.stdout; return ()
  | e -> print_endline (Printexc.to_string e); flush Pervasives.stdout; return ()



let rec accept sock =
  Lwt_unix.accept sock >>= fun (inp, _) ->
  Util.client_socket !host !port >>= fun out ->
  input_of_fd "Client socket" inp >>= fun i ->
  input_of_fd "Server socket" out >>= fun o ->
  let io = forward (empty_state "C->S") i out in
  let oi = forward (empty_state "S->C") o inp in
  catch (fun () -> pick [io; oi]) catcher >>= fun () ->
  ignore (Lwt_unix.close out);
  ignore (Lwt_unix.close inp);
  accept sock

let _ =
  let _ = parse_args getopt_params Sys.argv in
  let socket = Util.server_socket 8080 in
  Lwt_unix.run (accept socket)
