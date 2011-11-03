open Types
open Modules
open Printer
open NewParsingEngine
open TlsCommon


type tls_record_errors =
  | UnexpectedContentType

let tls_alert_errors_strings =
  [| (UnexpectedContentType, s_benign, "Unexpected content type") |]

let tls_record_emit = register_module_errors_and_make_emit_function "tlsAlert" tls_alert_errors_strings



(* Content type *)

type content_type =
  | CT_ChangeCipherSpec
  | CT_Alert
  | CT_Handshake
  | CT_ApplicationData
  | CT_Unknown of int

let string_of_content_type = function
  | CT_ChangeCipherSpec -> "ChangeCipherSpec"
  | CT_Alert -> "Alert"
  | CT_Handshake -> "Handshake"
  | CT_ApplicationData -> "ApplicationData"
  | CT_Unknown x -> "Unknown content type " ^ (string_of_int x)

let content_type_of_int pstate = function
  | 20 -> CT_ChangeCipherSpec
  | 21 -> CT_Alert
  | 22 -> CT_Handshake
  | 23 -> CT_ApplicationData
  | x ->
    tls_record_emit UnexpectedContentType (Some (string_of_int x)) pstate;
    CT_Unknown x





(* Record type *)

type record_type = {
  version : protocol_version;
  content_type : content_type;
  content : value
}



module RecordParser = struct
  let name = "record"
  type t = record_type

  let mk_ehf () = default_error_handling_function !tolerance !minDisplay

  (* TODO: Should disappear soon... *)
  type pstate = NewParsingEngine.parsing_state
  let pstate_of_string s = NewParsingEngine.pstate_of_string (mk_ehf ()) s
  let pstate_of_stream n s = NewParsingEngine.pstate_of_stream (mk_ehf ()) n s
  let eos = eos
  (* TODO: End of blob *)

  let parse pstate =
    let ctype = content_type_of_int pstate (pop_byte pstate) in
    let maj = pop_byte pstate in
    let min = pop_byte pstate in
    let len = extract_uint16 pstate in
    let content = extract_string (string_of_content_type ctype) len pstate in
    Some { version = {major = maj; minor = min};
	   content_type = ctype;
	   content = V_BinaryString content }

  let dump record = raise NotImplemented

  let enrich record dict =
    Hashtbl.replace dict "content_type" (V_String (string_of_content_type (record.content_type)));
    Hashtbl.replace dict "version" (V_String (string_of_protocol_version record.version));
    Hashtbl.replace dict "content" record.content;
    ()

  let update dict = raise NotImplemented

  let to_string r =
    "TLS Record (" ^ (string_of_protocol_version r.version) ^
      "): " ^ (string_of_content_type r.content_type) ^
      (match r.content with
	| V_BinaryString s | V_String s ->
	  "\n    Length:  " ^ (string_of_int (String.length s))
	| _ -> "") ^
      "\n    Content: " ^ (PrinterLib.string_of_value_aux "         " false r.content)


  let merge records =
    let rec merge_aux current accu records = match current, records with
      | None, [] -> []
      | Some r, [] -> List.rev (r::accu)
      | None, r::rem ->
	if r.content_type = CT_Handshake
	then merge_aux (Some r) accu rem
	else merge_aux None (r::accu) rem
      | Some r1, r2::rem ->
	if (r1.version = r2.version && r1.content_type = r2.content_type)
	(* TODO: Here we might lose some info about the exact history... *)
	then begin
	  let new_content = V_BinaryString ((eval_as_string r1.content) ^ (eval_as_string r2.content)) in
	  merge_aux (Some {r1 with content = new_content}) accu rem
	end else merge_aux None (r1::accu) records
    in merge_aux None [] records

  let params = []
end

module RecordModule = MakeParserModule (RecordParser)

let wrapped_merge records =
  let raw_records = List.map RecordModule.pop_object (eval_as_list records) in
  let merged_records = RecordParser.merge raw_records in
  let result = List.map RecordModule.register merged_records in
  V_List (result)

let _ =
  add_module ((module RecordModule : Module));
  RecordModule.populate_fun ("merge", one_value_fun wrapped_merge);
  ()