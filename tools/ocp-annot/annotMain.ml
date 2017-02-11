(**************************************************************************)
(*                                                                        *)
(*   Typerex Tools                                                        *)
(*                                                                        *)
(*   Copyright 2011-2017 OCamlPro SAS                                     *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU General Public License version 3 described in the file       *)
(*   LICENSE.                                                             *)
(*                                                                        *)
(**************************************************************************)

open AnnotParser

(************************************************************************)
(* Format: on the long term, we should support more than Emacs !        *)

type output =
| Int of int
| String of string
| Record of (string * output) list


module Emacs = struct
  let string_of_output v =
    let b = Buffer.create 100 in
    let rec iter v =
      match v with
      | Int n -> Printf.bprintf b "%d" n
      | String s -> Printf.bprintf b "%S" s
      | Record labels ->
        Printf.bprintf b "(";
        List.iter (fun (label, v) ->
          Printf.bprintf b "(:%s . " label;
          iter v;
          Printf.bprintf b ")"
        ) labels;
        Printf.bprintf b ")";
    in
    iter v;
    Buffer.contents b

end

let output_function = ref Emacs.string_of_output

(************************************************************************)
(* [query_pos "FILE:POS"] returns the information at FILE:POS sorted by
   the size of the expression *)

let query_at_pos file_pos =
  let file, pos = OcpString.cut_at file_pos ':' in
  let pos = int_of_string pos in
  let annot_file = (Filename.chop_extension file) ^ ".annot" in
  let locs = AnnotParser.parse_file annot_file in

  let rec iter infos locs =
    match locs with
    | [] -> infos
    | ( (file, (_,_, pos1), (_,_,pos2)), new_infos) :: locs ->
      if pos1 <= pos && pos2 >= pos then
        iter ( (pos2-pos1, (file, pos1, pos2, new_infos)) :: infos) locs
      else
        iter infos locs
  in
  let infos = iter [] locs in
  List.sort Pervasives.compare infos

(************************************************************************)
(* Query information on the expression at a given position              *)

let query_info file_pos =
  match query_at_pos file_pos with
  | [] -> raise Not_found
  | infos ->
    let rec iter infos =
      match infos with
      | [] -> []
      | (_, (file, pos1,pos2, kinds)) :: infos ->
        ( "left", Int pos1 ) ::
        ( "right", Int pos2 ) ::
        List.map (function
        | Type typ ->
          "type", String (String.concat "\n" typ)
        | Ident ident ->
          "ident", Record (
            match AnnotParser.parse_ident ident with
            | Def (ident, (_, (_,_,pos1), (_,_,pos2) )) ->
              [ "kind", String "def";
                "ident", String ident;
                "scope_begin", Int pos1;
                "scope_end", Int pos2 ]
            | ExtRef ident ->
              [ "kind", String "ext_ref";
                "ident", String ident ]
            | IntRef (ident, loc) ->
              [ "kind", String "int_ref";
                "ident", String ident;
                "def_begin", Int pos1;
                "def_end", Int pos2 ]
          )
        ) kinds
        @ [ "parent", Record (iter infos)]
    in
    let v = Record (iter infos) in
    Printf.printf "%s\n%!" (!output_function v)

(************************************************************************)
(* Query info to perform a jump to the identifier location              *)

let is_directory file = try Sys.is_directory file with _ -> false

let locate_ident src_file annot_file idents =
  let locs = AnnotParser.parse_file annot_file in
  let rec iter locs =
    match locs with
    | [] ->
      Printf.kprintf failwith
        "ocp-annot: cannot locate %S"
        (String.concat "." idents)
    | (loc, infos) :: locs ->
      iter_infos loc infos locs

  and iter_infos loc infos locs =
    match infos with
    | [] -> iter locs
    | Type _ :: infos -> iter_infos loc infos locs
    | Ident ident :: infos ->
      match AnnotParser.parse_ident ident with
      | IntRef _
      | ExtRef _ -> iter_infos loc infos locs
      | Def (ident, scope) ->
        match idents with
        | id :: _ when id = ident ->
          let (file, (_, _, pos), _) = loc in
          let ml_file =
            Filename.concat (Filename.dirname annot_file)
              (Filename.basename file) in
          [ "from_file", String src_file;
            "file", String ml_file;
            "pos", Int pos;
          ]
        | _ -> iter_infos loc infos locs
  in
  iter locs

let find_by_path src_file path =

  let path, _ = OcpString.cut_at path '(' in
  let path = OcpString.split path '.' in
  match path with
  | [] -> assert false
  | modname :: idents ->
    let file_path = OcpString.split src_file '/' in
    let file_path = match file_path with
      | ( "" | "." ) :: file_path -> file_path
      | _ -> file_path in
    let max_rec = min 3 (List.length file_path - 1) in
    let modname_annot = modname ^ ".annot" in
    let rec iter dir level =
      if level > max_rec then
        Printf.kprintf failwith
          "ocp-annot: file matching %S not found" modname
      else
        let files = Sys.readdir dir in
        let files = Array.to_list files in
        iter_files dir level files

    and iter_files dir level files =
      match files with
        [] -> iter (Filename.concat dir "..") (level+1)
      | file :: files ->
        let filename = Filename.concat dir file in
        if String.capitalize file = modname_annot then
          locate_ident src_file filename idents
        else
          if is_directory filename then
            iter_sub (dir,level,files) [] filename
          else
            iter_files dir level files

    and iter_sub dlf stack dir =
      let files = Sys.readdir dir in
      let files = Array.to_list files in
      iter_subfiles dlf stack dir files

    and iter_subfiles dlf stack dir files =
      match files with
        [] ->
          begin
            match stack with
            | [] ->
              let (dir, level, files) = dlf in
              iter_files dir level files
            | (dir, files) :: stack ->
              iter_subfiles dlf stack dir files
          end
      | file :: files ->
        let filename = Filename.concat dir file in
        if String.capitalize file = modname_annot then
          locate_ident src_file filename idents
        else
          if is_directory filename then
            iter_sub dlf ((dir,files) :: stack)
              filename
          else
            iter_subfiles dlf stack dir files

    in
    iter "." 0

let query_jump file_pos =
  match query_at_pos file_pos with
  | [] -> raise Not_found
  |  ( _, (file, pos1, pos2, infos) ) :: _ ->
    let rec iter infos =
      match infos with
      | [] -> raise Not_found
      | info :: infos ->
        match info with
        | Type _ -> iter infos
        | Ident ident ->
          match AnnotParser.parse_ident ident with
          | Def _ -> raise Not_found
          | IntRef (ident, location) ->
            let (_, (_,_,pos), (_,_,_) ) = location in
            [
              "ident", String ident;
              "pos", Int pos;
            ]
          | ExtRef path ->
            ("ident", String path) ::
              find_by_path file path
    in
    let v = Record (iter infos) in
    Printf.printf "%s\n%!" (!output_function v)


(************************************************************************)
(* Parse arguments and call actions                                     *)

let main () =
  Arg.parse [
    "--emacs", Arg.Unit (fun () -> output_function := Emacs.string_of_output),
    " Output for Emacs";
    "--query-info", Arg.String query_info,
    "FILE:POS Query info at pos";
    "--query-jump", Arg.String query_jump,
    "FILE:POS Query jump info at pos";
  ] (fun filename ->
    let locs = AnnotParser.parse_file filename in
    ()
  ) ""

let () =
  try
    main ()
  with exn ->
    let bt = Printexc.get_backtrace () in
    let oc =
      open_out_gen [ Open_creat; Open_append ] 0o644 "/tmp/ocp-annot.log" in
    Printf.fprintf oc
      "'%s'\n" (String.concat "' '"
                  (Array.to_list Sys.argv));
    Printf.fprintf oc
      "Error: exception %s\n" (Printexc.to_string exn);
    if bt <> "" then
      Printf.fprintf oc "Backtrace:\n%s\n%!" bt;
    close_out oc;
    let infos = [ "error",
                  String (Printf.sprintf "Error: exception %s"
                            (Printexc.to_string exn)) ] in
    let v = Record infos in
    Printf.printf "%s\n%!" (!output_function v)
