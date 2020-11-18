(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2020 OCamlPro SAS & Origin Labs SAS                     *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Lesser General    *)
(*  Public License version 2.1, with the special exception on linking     *)
(*  described in the LICENSE.md file in the root directory.               *)
(*                                                                        *)
(**************************************************************************)

(*
  DONE:
  * find all installed opam packages
  * read changes files to discover ownership of files by opam packages
  * read all META files associated with opam packages
  * associate .cma/.cmxa files to meta packages and opam packages

  TODO:
  * read opam files for direct dependencies between opam packages
  * use ocamlobjinfo to detect modules provided by libraries

*)

open EzCompat
open EzFile.OP
open Types

let cache_file = "_digodoc/digodoc.state"

let main () =

  let opam_switch_prefix = lazy
    (
      try Sys.getenv "OPAM_SWITCH_PREFIX"
      with Not_found -> failwith "not in an opam switch"
    )
  in

  let get_state ~state ~objinfo =
    match state with
    | None ->
        let opam_switch_prefix = Lazy.force opam_switch_prefix in
        let state = Compute.compute ~opam_switch_prefix ~objinfo () in
        if objinfo then begin
          EzFile.make_dir ~p:true "_digodoc";
          let oc = open_out_bin cache_file in
          output_value oc ( state : state );
          close_out oc;
        end;
        state
    | Some state -> state
  in
  let help exit_code =
    Printf.eprintf
      {|
digodoc [--html] [--www] [--cached] [--no-objinfo] [--help] [MODULE]

Options:
--html: build html documentation
--www: open html documentation in a browser
--cached: use the cached state instead of recomputing it
--no-objinfo: do not call ocamlobjinfo to attach modules to libraries

If a MODULE is provided, display the source module corresponding to this module

%!|};
    exit exit_code
  in
  let rec iter ~state ~objinfo args =
    match args with
    | [] ->
        let state = get_state ~state ~objinfo in
        Printer.print state
    | "--no-objinfo" :: args ->
        iter ~state ~objinfo:false args
    | "--cached" :: args ->
        let state =
          let ic = open_in_bin cache_file  in
          let ( state : state ) = input_value ic in
          close_in ic;
          Some state
        in
        iter ~state ~objinfo args
    | ( "--help" | "-h" | "-help" ) :: _ -> help 0
    | _ :: _ :: _ ->
        help 2
    | [ "--html" ] ->
        let state = get_state ~state ~objinfo in
        Odoc.generate ~state
    | [ "--www" ] ->
        let index = Odoc.digodoc_html_dir // "index.html" in
        if Sys.file_exists index then
          Process.call [| "xdg-open" ; index |]
        else begin
          Printf.eprintf
            "Error: Use `digodoc --html` to generate the documentation first.\n";
          exit 2
        end
    | [ mdl ] ->
        let state = get_state ~state ~objinfo:false in
        match Hashtbl.find_all state.ocaml_mdls_by_name mdl with
        | exception Not_found -> failwith "module not found"
        | [ m ] ->
            let opam_switch_prefix = Lazy.force opam_switch_prefix in
            if StringSet.mem "mli" m.mdl_exts then
              Unix.execvp "less" [| "less";
                                    opam_switch_prefix //
                                    ( Module.file m "mli") |]
            else
            if StringSet.mem "ml" m.mdl_exts then
              Unix.execvp "less" [| "less";
                                    opam_switch_prefix //
                                    ( Module.file m "ml") |]
        | list ->
            Printf.printf "Found %d occurences of %S:\n%!"
              ( List.length list) mdl;
            List.iter (fun m ->
                Printf.printf "* %s::%s\n%!"
                  m.mdl_opam.opam_name m.mdl_name
              ) list;
            exit 0
  in

  let args = Sys.argv |> Array.to_list |> List.tl in
  iter ~state:None ~objinfo:true args