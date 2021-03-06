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

type ansi_sequences = {
  mutable esc_ansi : bool;
  mutable esc_bold : string;
  mutable esc_black_text : string;
  mutable esc_red_text : string;
  mutable esc_green_text : string;
  mutable esc_yellow_text : string;
  mutable esc_blue_text : string;
  mutable esc_magenta_text : string;
  mutable esc_cyan_text : string;
  mutable esc_white_text : string;
  mutable esc_end : string;
  mutable esc_linefeed : string;
  mutable esc_killline : string;
  mutable esc_columns : int;
}

val term : ansi_sequences
val set_ansi_term : bool -> unit
val term_bold : string -> string
val term_escape : string -> string



