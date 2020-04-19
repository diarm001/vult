(*
   The MIT License (MIT)

   Copyright (c) 2020 Leonardo Laguna Ruiz

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

type path =
  { id : string
  ; n : string option
  ; loc : Loc.t [@compare fun _ _ -> 0]
  }
[@@deriving show, eq, ord]

type type_d =
  | STId       of path
  | STSize     of int
  | STComposed of string * type_ list
[@@deriving show, eq, ord]

and type_ =
  { t : type_d
  ; loc : Loc.t
  }
[@@deriving show, eq, ord]

type tag_d =
  | SGId     of string
  | SGInt    of int
  | SGBool   of bool
  | SGReal   of float
  | SGString of string
  | SGCall   of
      { name : string
      ; args : (string * tag * Loc.t) list
      }
[@@deriving show, eq, ord]

and tag =
  { g : tag_d
  ; loc : Loc.t
  }
[@@deriving show, eq, ord]

type exp_d =
  | SEUnit
  | SEBool   of bool
  | SEInt    of int
  | SEReal   of float
  | SEString of string
  | SEId     of string
  | SEIndex  of
      { e : exp
      ; index : exp
      }
  | SEArray  of exp list
  | SECall   of
      { instance : string option
      ; path : path
      ; args : exp list
      }
  | SEUnOp   of string * exp
  | SEOp     of string * exp * exp
  | SEIf     of
      { cond : exp
      ; then_ : exp
      ; else_ : exp
      }
  | SETuple  of exp list
  | SEMember of exp * string
  | SEGroup  of exp
[@@deriving show, eq, ord]

and exp =
  { e : exp_d
  ; loc : Loc.t
  }
[@@deriving show, eq, ord]

and lexp_d =
  | SLWild
  | SLId     of string
  | SLMember of lexp * string
  | SLIndex  of
      { e : lexp
      ; index : exp
      }
  | SLGroup  of lexp
  | SLTuple  of lexp list
[@@deriving show, eq, ord]

and lexp =
  { l : lexp_d
  ; loc : Loc.t
  }
[@@deriving show, eq, ord]

type dexp_d =
  | SDWild
  | SDId    of string * int option
  | SDTuple of dexp list
  | SDGroup of dexp
  | SDTyped of dexp * type_
[@@deriving show, eq, ord]

and dexp =
  { d : dexp_d
  ; loc : Loc.t
  }
[@@deriving show, eq, ord]

type arg = string * type_ option * Loc.t [@@deriving show, eq, ord]

and stmt_d =
  | SStmtError
  | SStmtVal    of dexp * exp option
  | SStmtMem    of dexp * exp option * tag list
  | SStmtBind   of lexp * exp
  | SStmtReturn of exp
  | SStmtBlock  of stmt list
  | SStmtIf     of exp * stmt * stmt option
  | SStmtWhile  of exp * stmt
[@@deriving show, eq, ord]

and stmt =
  { s : stmt_d
  ; loc : Loc.t
  }
[@@deriving show, eq, ord]

and function_def =
  { name : string
  ; args : arg list
  ; t : type_ option
  ; next : (function_def * stmt) option
  ; loc : Loc.t
  ; tags : tag list
  }
[@@deriving show, eq, ord]

type top_stmt_d =
  | STopError
  | STopExternal of function_def * string option
  | STopFunction of function_def * stmt
  (*| STopTypeAlias of string * type_*)
  | STopType     of
      { name : string
      ; members : (string * type_ * Loc.t) list
      }
[@@deriving show, eq, ord]

and top_stmt =
  { top : top_stmt_d
  ; loc : Loc.t
  }
[@@deriving show, eq, ord]

type stmts = top_stmt list [@@deriving show, eq, ord]