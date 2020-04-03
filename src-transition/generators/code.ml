(*
   The MIT License (MIT)

   Copyright (c) 2014 Leonardo Laguna Ruiz

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.
*)

(** Intermedia representation for the target languages *)

type cattr = { is_root : bool } [@@deriving show, eq, ord]

(** Description of types *)
type type_descr =
   | CTSimple of string
   | CTArray  of type_descr * int
[@@deriving show, eq, ord]

(** Description of arguments to functions *)
type arg_type =
   | Ref of type_descr
   | Var of type_descr
[@@deriving show, eq, ord]

(** Description of expressions (rhs) *)
type cexp =
   | CEInt    of int
   | CEFloat  of string * float
   | CEBool   of bool
   | CEString of string
   | CEArray  of cexp list * type_descr
   | CECall   of string * cexp list * type_descr
   | CEUnOp   of string * cexp * type_descr
   | CEOp     of string * cexp list * type_descr
   | CEVar    of string * type_descr
   | CEIndex  of cexp * cexp * type_descr
   | CEIf     of cexp * cexp * cexp * type_descr
   | CETuple  of (string * cexp) list * type_descr
   | CEAccess of cexp * string
   | CEEmpty
[@@deriving show, eq, ord]

(** Description of expressions (lhs) *)
and clhsexp =
   | CLWild
   | CLId    of type_descr * string list
   | CLTuple of clhsexp list
   | CLIndex of type_descr * string list * cexp
[@@deriving show, eq, ord]

(** Description of statements *)
type cstmt =
   | CSVar      of clhsexp * cexp option
   | CSConst    of clhsexp * cexp
   | CSBind     of clhsexp * cexp
   | CSFunction of type_descr * string * (arg_type * string) list * cstmt * cattr
   | CSReturn   of cexp
   | CSWhile    of cexp * cstmt
   | CSBlock    of cstmt list
   | CSIf       of cexp * cstmt * cstmt option
   | CSType     of string * (type_descr * string) list * cattr
   | CSAlias    of string * type_descr
   | CSExtFunc  of type_descr * string * (arg_type * string) list
   | CSSwitch   of cexp * (cexp * cstmt) list * cstmt option
   | CSEmpty
[@@deriving show, eq, ord]
