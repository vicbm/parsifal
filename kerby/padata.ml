open Lwt
open Parsifal
open PTypes
open Asn1PTypes
open Asn1Engine
open X509
open X509Basics
open X509Extensions
open Pkcs7

(* ContextSpecific optimization *)
type 'a cspe = 'a
let parse_cspe n parse_fun input = parse_asn1 (C_ContextSpecific, true, T_Unknown n) parse_fun input
let dump_cspe n dump_fun buf o = dump_asn1 (C_ContextSpecific, true, T_Unknown n) dump_fun buf o
let value_of_cspe = BasePTypes.value_of_container

(* DEFINITIONS *)
(* Define KerberosString *)
asn1_alias der_kerberos_string = primitive[T_GeneralString] der_printable_octetstring_content(no_constraint)
(* Define Sequence of KerberosString *)
asn1_alias seqkerbstring = seq_of der_kerberos_string
(* Define KerberosTime *)
alias der_kerberos_time = der_time


asn1_struct pk_authenticator =
{
  cusec : cspe [0] of der_smallint;
  ctime : cspe [1] of der_kerberos_time;
  nonce : cspe [2] of der_smallint; (* Chosen randomly, does not need to match KDC-REQ-BODY one *)
  optional pa_checksum : cspe[3] of der_octetstring (* SHA1 checksum or KDC-REQ-BODY *)
}

asn1_struct myoid =
{
  oid : cspe [0] of der_oid
}

asn1_alias oid_list = seq_of myoid

asn1_struct auth_pack = {
  pk_authenticator : cspe [0] of pk_authenticator;
  clientPublicKeyValue : cspe [1] of subjectPublicKeyInfo;
  optional supported_cms_types : cspe [2] of sMIMECapabilities;
  (* FIXME Decode the two structures *)
  optional client_dh_nonce : cspe[3] of binstring;
  optional supported_KDFs : cspe[4] of oid_list
}

asn1_struct kdc_dh_key_info = {
  subject_public_key : cspe [0] of der_bitstring;
  nonce : cspe [1] of der_smallint;
  optional dh_key_expiration : cspe [2] of der_kerberos_time
}

union krbContentInfo_value [enrich] (UnparsedKrbContentInfo of binstring) =
 | [43;6;1;5;2;3;1] -> ID_PKINIT_AuthData of auth_pack
 | [43;6;1;5;2;3;2] -> ID_PKINIT_DHKeyData of kdc_dh_key_info

asn1_struct krbContentInfo = {
  oid : der_oid;
  contentInfo : asn1 [(C_ContextSpecific, true, T_Unknown 0)] of octetstring_container of krbContentInfo_value(oid)
}

struct mysignerInfo_content = {
  version : der_smallint;
  (* FIXME Ugly hack, because Heimdal does not seem to use normal issuerAndSerial structure *)
  (* issuerAndSerialNumber : issuerAndSerialNumber; *)
  issuerAndSerialNumber_FIXME : der_object;
  digestAlgorithm : algorithmIdentifier;
  optional authenticatedAttributesUNPARSED : authenticatedAttributes;
  digestEncryptionAlgorithm : algorithmIdentifier;
  encryptedDigest : der_octetstring;
  optional unAuthenticatedAttributesUNPARSED : unauthenticatedAttributes
}
asn1_alias mysignerInfo

asn1_struct kerb_pkcs7_signed_data = {
  version : der_smallint;
  digestAlgorithms : digestAlgorithmIdentifiers;
  contentInfo : krbContentInfo;
  optional certificates : asn1 [(C_ContextSpecific, true, T_Unknown 0)] of (list of certificate);
  optional crls : asn1 [(C_ContextSpecific, true, T_Unknown 0)] of (list of binstring);
  (* FIXME Ugly hack, because Heimdal does not seem to use normal issuerAndSerial structure *)
  signerInfos : asn1 [(C_Universal, true, T_Set)] of (list of mysignerInfo);
}

asn1_struct kerb_pkcs7 = {
  p7_contenttype : der_oid;
  (*p7_content : pkcs7_content*)
  p7_signed_data : cspe [0] of kerb_pkcs7_signed_data
}

enum etype_type (8, UnknownVal UnknownEncryptType) =
  | 1  -> DES_CBC_CRC
  | 2  -> DES_CBC_MD4
  | 3  -> DES_CBC_MD5
  | 5  -> DES3_CBC_MD5
  | 16 -> DES3_CBC_SHA1
  | 17 -> AES128_CTS_HMAC_SHA1_96
  | 18 -> AES256_CTS_HMAC_SHA1_96
  | 23 -> RC4_HMAC
  | 24 -> RC4_HMAC_EXP
  | 25 -> CAMELLIA128_CTS_CMAC
  | 26 -> CAMELLIA256_CTS_CMAC

struct externalPrincipalIdentifier_content = {
 optional subjectName : asn1 [(C_ContextSpecific, false, T_Unknown 0)] of distinguishedName;
 optional issuerAndSerialNumber : asn1 [(C_ContextSpecific, false, T_Unknown 1)] of issuerAndSerialNumber;
 optional subjectKeyIdentifier : asn1 [(C_ContextSpecific, false, T_Unknown 2)] of der_octetstring;
}
asn1_alias externalPrincipalIdentifier
asn1_alias externalPrincipalIdentifiers = seq_of externalPrincipalIdentifier

asn1_struct pa_pk_as_req =
{
  (*
  signed_auth_pack_TOFIX : asn1 [(C_ContextSpecific, false, T_Unknown 0)] of binstring;
  *)
  (* TODO better test CMS (PKCS#7) *)
  signed_auth_pack : asn1 [(C_ContextSpecific, false, T_Unknown 0)] of kerb_pkcs7;
  trusted_certifiers : cspe [1] of externalPrincipalIdentifiers;
  optional kdc_pk_id : cspe [2] of binstring
}

asn1_struct dhrepinfo = 
{
  dh_signed_data : asn1 [(C_ContextSpecific, false, T_Unknown 0)] of kerb_pkcs7;
  optional server_dh_nonce : cspe [1] of binstring;
  optional kdf_id : cspe [2] of myoid
}

struct pa_pk_as_rep =
{
  dhinfo : cspe [0] of dhrepinfo
  (*
  (* or (ASN.1 CHOICE ! *)
  enckeypack : asn1 [(C_ContextSpecific, false, T_Unknown 0)] of binstring
  pa_pk_as_rep_FIXME : binstring
  *)
}

struct etype_info2_content =
{
  etype : cspe [0] of asn1 [(C_Universal, false, T_Integer)] of etype_type;
  optional salt : cspe [1] of der_kerberos_string;
  optional s2kparams : cspe [2] of der_octetstring
}
asn1_alias etype_info2
asn1_alias etype_info2s = seq_of etype_info2

(* DEBUG pa_pk_as_rep *)
(*
let parse_pa_pk_as_rep input =
  let o = input.cur_offset in
  Printf.printf "%s\n" (hexdump (BasePTypes.parse_rem_string input));
  input.cur_offset <- o;
  parse_pa_pk_as_rep input
*)

let kerberos_oids = [
  "Diffie-Hellman Key Exchange" , [42;840;10046;2;1];
  "id-pkinit-san", [43;6;1;5;2;2];
  "id-pkinit-authData",  [43;6;1;5;2;3;1];
  "id-pkinit-DHKeyData",  [43;6;1;5;2;3;2];
  "id-pkinit-kdf-ah-sha1",  [43;6;1;5;2;3;6;1];
  "id-pkinit-kdf-ah-sha256",  [43;6;1;5;2;3;6;2];
  "id-pkinit-kdf-ah-sha512",  [43;6;1;5;2;3;6;3];
  "id-pkinit-kdf-ah-sha384",  [43;6;1;5;2;3;6;4];
]

let handle_entry input =
  let padata = parse_kerb_pkcs7 input in
  print_endline (print_value (value_of_kerb_pkcs7 padata))

let _ = 
  let register_oids (name, oid) = register_oid oid name in
    List.map register_oids kerberos_oids;

(*
let main () =
  let input = string_input_of_filename "p7blob" in
  handle_entry input
*)
(*
let _ = main ()
*)
