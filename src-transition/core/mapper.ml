(*
   The MIT License (MIT)

   Copyright (c) 2014 Leonardo Laguna Ruiz, Carl Jönsson

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

open Prog
open Env

let log = false

type ('data, 'kind) mapper_func = (string * ('data -> 'kind -> 'data * 'kind)) option

type ('data, 'kind) expand_func = (string * ('data -> 'kind -> 'data * 'kind list)) option

let apply (mapper : ('data, 'kind) mapper_func) (data : 'data) (kind : 'kind) : 'data * 'kind =
   match mapper with
   | Some ("", f) -> f data kind
   | Some (name, f) ->
      let d, k = f data kind in
      begin
         if log && not (kind == k) then
            let () = Printf.printf "- %s applied\n" name in
            flush stdout
      end ;
      d, k
   | None -> data, kind


let applyExpander (mapper : ('data, 'kind) expand_func) (data : 'data) (kind : 'kind) : 'data * 'kind list =
   match mapper with
   | Some ("", f) -> f data kind
   | Some (name, f) ->
      let d, k = f data kind in
      ( if log then
           match k with
           | [ k' ] when k' == kind -> ()
           | _ -> Printf.printf "- %s applied\n" name ) ;
      d, k
   | None -> data, [ kind ]


let applyExpanderList (mapper : ('data, 'kind) expand_func) (data : 'data) (kind_list : 'kind list) : 'data * 'kind list
   =
   let state', rev_exp_list =
      List.fold_left
         (fun (s, acc) k ->
             let s', kl = applyExpander mapper s k in
             let kl' =
                match kl with
                | [ StmtBlock (None, kl', _) ] -> kl'
                | _ -> kl
             in
             s', kl' :: acc)
         (data, [])
         kind_list
   in
   state', rev_exp_list |> List.rev |> List.flatten


let make (name : string) (mapper : 'data -> 'kind -> 'data * 'kind) : ('data, 'kind) mapper_func = Some (name, mapper)

let makeExpander (name : string) (mapper : 'data -> 'kind -> 'data * 'kind list) : ('data, 'kind) expand_func =
   Some (name, mapper)


(** Makes a chain of mappers. E.g. foo |-> bar will apply first foo then bar. *)
let ( |-> ) : ('data, 'value) mapper_func -> ('data, 'value) mapper_func -> ('data, 'value) mapper_func =
   fun mapper1 mapper2 ->
   let mapper3 state exp =
      let state', exp' = apply mapper1 state exp in
      apply mapper2 state' exp'
   in
   Some ("", mapper3)


let ( |*> ) : ('data, 'value) expand_func -> ('data, 'value) expand_func -> ('data, 'value) expand_func =
   fun mapper1 mapper2 ->
   let mapper3 state exp =
      let state', exp_list = applyExpander mapper1 state exp in
      let state', exp_list' = applyExpanderList mapper2 state' exp_list in
      state', exp_list'
   in
   Some ("", mapper3)


type 'a mapper =
   { vtype_c : ('a, Typ.vtype) mapper_func
   ; typed_id : ('a, typed_id) mapper_func
   ; exp : ('a, exp) mapper_func
   ; lhs_exp : ('a, lhs_exp) mapper_func
   ; val_decl : ('a, val_decl) mapper_func
   ; stmt : ('a, stmt) mapper_func
   ; attr : ('a, attr) mapper_func
   ; id : ('a, Id.t) mapper_func
   ; stmt_x : ('a, stmt) expand_func
   }

let default_mapper =
   { vtype_c = None
   ; typed_id = None
   ; exp = None
   ; lhs_exp = None
   ; val_decl = None
   ; stmt = None
   ; attr = None
   ; id = None
   ; stmt_x = None
   }


(** Merge two mapper functions. This is a little bit weird but it will be
    improved when mapper functions are optional. *)
let seqMapperFunc a b =
   if a = None then
      b
   else if b = None then
      a
   else
      a |-> b


let seqExpandFunc a b =
   if a = None then
      b
   else if b = None then
      a
   else
      a |*> b


(** Merges two mappers *)
let seq (b : 'a mapper) (a : 'a mapper) : 'a mapper =
   { vtype_c = seqMapperFunc a.vtype_c b.vtype_c
   ; typed_id = seqMapperFunc a.typed_id b.typed_id
   ; exp = seqMapperFunc a.exp b.exp
   ; lhs_exp = seqMapperFunc a.lhs_exp b.lhs_exp
   ; val_decl = seqMapperFunc a.val_decl b.val_decl
   ; stmt = seqMapperFunc a.stmt b.stmt
   ; attr = seqMapperFunc a.attr b.attr
   ; id = seqMapperFunc a.id b.id
   ; stmt_x = seqExpandFunc a.stmt_x b.stmt_x
   }


(** Applies any mapper to a list *)
let mapper_list mapper_app mapper state el =
   let state', rev_el =
      List.fold_left
         (fun (s, acc) e ->
             let s', e' = mapper_app mapper s e in
             s', e' :: acc)
         (state, [])
         el
   in
   state', List.rev rev_el


(** Applies any mapper to an array *)
let mapper_array mapper_app mapper state el =
   let ret = Array.copy el in
   let state', _ =
      Array.fold_left
         (fun (s, i) e ->
             let s', e' = mapper_app mapper s e in
             ret.(i) <- e' ;
             s', i + 1)
         (state, 0)
         el
   in
   state', ret


(** Applies any mapper to an option value *)
let mapper_opt mapper_app mapper state e_opt =
   match e_opt with
   | None -> state, None
   | Some e ->
      let state', e' = mapper_app mapper state e in
      state', Some e'


let map_id (mapper : 'a mapper) (state : 'a) (id : Id.t) : 'a * Id.t = apply mapper.id state id

let rec map_attr (mapper : 'a mapper) (state : 'a) (attr : attr) : 'a * attr =
   let state', tp' = (mapper_opt map_vtype) mapper state attr.typ in
   apply mapper.attr state' { attr with typ = tp' }


and map_vtype_c (mapper : 'a mapper) (state : 'a) (te : Typ.vtype) : 'a * Typ.vtype =
   let map_vtype_list = mapper_list map_vtype in
   match te with
   | Typ.TInt (_, _)
   |Typ.TUnbound (_, _, _) ->
      state, te
   | Typ.TId (id, loc) ->
      let state', id' = map_id mapper state id in
      apply mapper.vtype_c state' (Typ.TId (id', loc))
   | Typ.TComposed (id, el, loc) ->
      let state', id' = map_id mapper state id in
      let state', el' = map_vtype_list mapper state' el in
      apply mapper.vtype_c state' (Typ.TComposed (id', el', loc))
   | Typ.TArrow (e1, e2, loc) ->
      let state', e1' = map_vtype mapper state e1 in
      let state', e2' = map_vtype mapper state' e2 in
      apply mapper.vtype_c state' (Typ.TArrow (e1', e2', loc))
   | Typ.TLink tp ->
      let state', tp' = map_vtype mapper state tp in
      apply mapper.vtype_c state' (Typ.TLink tp')
   | Typ.TExpAlt elems ->
      let state', elems' = mapper_list map_vtype mapper state elems in
      apply mapper.vtype_c state' (Typ.TExpAlt elems')


and map_vtype (mapper : 'a mapper) (state : 'a) (te : Typ.t) : 'a * Typ.t =
   let state', tp = map_vtype_c mapper state !te in
   te := tp ;
   state', te


let map_type_list (mapper : 'a mapper) (state : 'a) (te : Typ.t list) : 'a * Typ.t list =
   mapper_list map_vtype mapper state te


let rec map_typed_id (mapper : 'a mapper) (state : 'a) (t : typed_id) : 'a * typed_id =
   match t with
   | SimpleId (id, kind, attr) ->
      let state', id' = map_id mapper state id in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.typed_id state' (SimpleId (id', kind, attr'))
   | TypedId (id, tp, kind, attr) ->
      let state', id' = map_id mapper state id in
      let state', tp' = map_type_list mapper state' tp in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.typed_id state' (TypedId (id', tp', kind, attr'))


let map_instance (mapper : 'state mapper) (state : 'state) (inst : instance) : 'state * instance =
   match inst with
   | NoInst -> state, inst
   | This -> state, inst
   | Named id ->
      let state, id = map_id mapper state id in
      state, Named id


let rec map_lhs_exp (mapper : 'state mapper) (state : 'state) (exp : lhs_exp) : 'state * lhs_exp =
   let map_lhs_exp_list = mapper_list map_lhs_exp in
   match exp with
   | LWild attr ->
      let state', attr' = map_attr mapper state attr in
      apply mapper.lhs_exp state' (LWild attr')
   | LId (id, tp, attr) ->
      let state', id' = map_id mapper state id in
      let state', tp' = (mapper_opt map_vtype) mapper state' tp in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.lhs_exp state' (LId (id', tp', attr'))
   | LTyped (e, tp, attr) ->
      let state', e' = map_lhs_exp mapper state e in
      let state', tp' = map_vtype mapper state' tp in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.lhs_exp state' (LTyped (e', tp', attr'))
   | LTuple (elems, attr) ->
      let state', elems' = map_lhs_exp_list mapper state elems in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.lhs_exp state' (LTuple (elems', attr'))
   | LGroup (e, attr) ->
      let state', attr' = map_attr mapper state attr in
      let state', e' = map_lhs_exp mapper state' e in
      apply mapper.lhs_exp state' (LGroup (e', attr'))
   | LIndex (id, tp, index, attr) ->
      let state', id' = map_id mapper state id in
      let state', tp' = (mapper_opt map_vtype) mapper state' tp in
      let state', index' = map_exp mapper state' index in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.lhs_exp state' (LIndex (id', tp', index', attr'))


and map_lhs_exp_list mapper state exp = (mapper_list map_lhs_exp) mapper state exp

and map_val_decl (mapper : 'state mapper) (state : 'state) (v : val_decl) : 'state * val_decl =
   let id, tp, attr = v in
   let state', id' = map_id mapper state id in
   let state', tp' = map_vtype mapper state' tp in
   let state', attr' = map_attr mapper state' attr in
   state', (id', tp', attr')


(** Traverses the expression in a bottom-up fashion *)
and map_exp (mapper : 'state mapper) (state : 'state) (exp : exp) : 'state * exp =
   match exp with
   | PUnit attr ->
      let state', attr' = map_attr mapper state attr in
      apply mapper.exp state' (PUnit attr')
   | PBool (b, attr) ->
      let state', attr' = map_attr mapper state attr in
      apply mapper.exp state' (PBool (b, attr'))
   | PInt (i, attr) ->
      let state', attr' = map_attr mapper state attr in
      apply mapper.exp state' (PInt (i, attr'))
   | PReal (r, precision, attr) ->
      let state', attr' = map_attr mapper state attr in
      apply mapper.exp state' (PReal (r, precision, attr'))
   | PString (s, attr) ->
      let state', attr' = map_attr mapper state attr in
      apply mapper.exp state' (PString (s, attr'))
   | PId (id, attr) ->
      let state', id' = map_id mapper state id in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PId (id', attr'))
   | PIndex (e, index, attr) ->
      let state', e' = map_exp mapper state e in
      let state', index' = map_exp mapper state' index in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PIndex (e', index', attr'))
   | PArray (elems, attr) ->
      let state', elems' = map_exp_array mapper state elems in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PArray (elems', attr'))
   | PEmpty -> apply mapper.exp state exp
   | PUnOp (op, e, attr) ->
      let state', e' = map_exp mapper state e in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PUnOp (op, e', attr'))
   | POp (op, args, attr) ->
      let state', args' = map_exp_list mapper state args in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (POp (op, args', attr'))
   | PCall (inst, name, args, attr) ->
      let state', inst' = map_instance mapper state inst in
      let state', name' = map_id mapper state' name in
      let state', args' = map_exp_list mapper state' args in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PCall (inst', name', args', attr'))
   | PIf (cond, then_, else_, attr) ->
      let state', cond' = map_exp mapper state cond in
      let state', then_' = map_exp mapper state' then_ in
      let state', else_' = map_exp mapper state' else_ in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PIf (cond', then_', else_', attr'))
   | PGroup (e, attr) ->
      let state', e' = map_exp mapper state e in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PGroup (e', attr'))
   | PAccess (e, m, attr) ->
      let state', e' = map_exp mapper state e in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PAccess (e', m, attr'))
   | PTuple (el, attr) ->
      let state', el' = map_exp_list mapper state el in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PTuple (el', attr'))
   | PSeq (id, stmt, attr) ->
      let state', id' = (mapper_opt map_id) mapper state id in
      let state', stmt' = map_stmt mapper state' stmt in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.exp state' (PSeq (id', stmt', attr'))


and map_exp_list mapper state exp = (mapper_list map_exp) mapper state exp

and map_exp_array mapper state exp = (mapper_array map_exp) mapper state exp

and map_stmt (mapper : 'state mapper) (state : 'state) (stmt : stmt) : 'state * stmt =
   match stmt with
   | StmtVal (lhs, rhs, attr) ->
      let state', lhs' = map_lhs_exp mapper state lhs in
      let state', rhs' = (mapper_opt map_exp) mapper state' rhs in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.stmt state' (StmtVal (lhs', rhs', attr')) |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtMem (lhs, rhs, attr) ->
      let state', lhs' = map_lhs_exp mapper state lhs in
      let state', rhs' = (mapper_opt map_exp) mapper state' rhs in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.stmt state' (StmtMem (lhs', rhs', attr')) |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtReturn (e, attr) ->
      let state', e' = map_exp mapper state e in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.stmt state' (StmtReturn (e', attr')) |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtBind (lhs, rhs, attr) ->
      let state', lhs' = map_lhs_exp mapper state lhs in
      let state', rhs' = map_exp mapper state' rhs in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.stmt state' (StmtBind (lhs', rhs', attr')) |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtType (name, members, attr) ->
      let base_name = Typ.base name in
      let state' = Env.enter Scope.Type state base_name emptyAttr in
      let state', name' = map_vtype mapper state' name in
      let state', members' = (mapper_list map_val_decl) mapper state' members in
      let state', attr' = map_attr mapper state' attr in
      let state', stmt' = apply mapper.stmt state' (StmtType (name', members', attr')) in
      let state' = Env.exit state' in
      (state', stmt') |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtAliasType (name, tp, attr) ->
      let base_name = Typ.base name in
      let state' = Env.enter Scope.Type state base_name emptyAttr in
      let state', name' = map_vtype mapper state' name in
      let state', tp' = map_vtype mapper state' tp in
      let state', attr' = map_attr mapper state' attr in
      let state', stmt' = apply mapper.stmt state' (StmtAliasType (name', tp', attr')) in
      let state' = Env.exit state' in
      (state', stmt') |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtEmpty -> apply mapper.stmt state StmtEmpty |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtWhile (cond, stmts, attr) ->
      let state', cond' = map_exp mapper state cond in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.stmt state' (StmtWhile (cond', stmts, attr')) |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtIf (cond, then_, Some else_, attr) ->
      let state', cond' = map_exp mapper state cond in
      let state' = Env.enterIf state' in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.stmt state' (StmtIf (cond', then_, Some else_, attr')) |> map_stmt_subs mapper |> map_stmt_x mapper
   | StmtIf (cond, then_, None, attr) ->
      let state', cond' = map_exp mapper state cond in
      let state', attr' = map_attr mapper state' attr in
      let state', stmt' =
         apply mapper.stmt state' (StmtIf (cond', then_, None, attr')) |> map_stmt_subs mapper |> map_stmt_x mapper
      in
      let state' = Env.exitIf state' in
      state', stmt'
   | StmtFun (name, args, body, ret, attr) ->
      let state' = Env.enter Scope.Function state name emptyAttr in
      let state', name' = map_id mapper state' name in
      let state', args' = (mapper_list map_typed_id) mapper state' args in
      let state', ret' = (mapper_opt map_vtype) mapper state' ret in
      let state', attr' = map_attr mapper state' attr in
      let state', stmt' =
         apply mapper.stmt state' (StmtFun (name', args', body, ret', attr')) |> map_stmt_subs mapper
      in
      let state' = Env.exit state' in
      (state', stmt') |> map_stmt_x mapper
   | StmtExternal (name, args, ret, linkname, attr) ->
      let state' = Env.enter Scope.Function state name emptyAttr in
      let state', name' = map_id mapper state' name in
      let state', args' = (mapper_list map_typed_id) mapper state' args in
      let state', ret' = map_vtype mapper state' ret in
      let state', attr' = map_attr mapper state' attr in
      let state', stmt' =
         apply mapper.stmt state' (StmtExternal (name', args', ret', linkname, attr')) |> map_stmt_subs mapper
      in
      let state' = Env.exit state' in
      (state', stmt') |> map_stmt_x mapper
   | StmtBlock (name, stmts, attr) ->
      let state', name' = (mapper_opt map_id) mapper state name in
      let state', attr' = map_attr mapper state' attr in
      apply mapper.stmt state' (StmtBlock (name', stmts, attr')) |> map_stmt_subs mapper |> map_stmt_x mapper


and map_stmt_list mapper state stmts =
   let state', stmts' = (mapper_list map_stmt) mapper state stmts in
   let state', stmts' = applyExpanderList mapper.stmt_x state' stmts' in
   state', stmts'


and map_stmt_x mapper (state, stmt) =
   let state', stmts' = applyExpander mapper.stmt_x state stmt in
   match stmts' with
   | [ (StmtBlock _ as b) ] -> state', b
   | [ stmt' ] -> state', stmt'
   | _ -> state', StmtBlock (None, stmts', emptyAttr)


and map_stmt_subs (mapper : 'state mapper) ((state, stmt) : 'state * stmt) : 'state * stmt =
   match stmt with
   | StmtVal _
   |StmtMem _
   |StmtReturn _
   |StmtBind _
   |StmtType _
   |StmtAliasType _
   |StmtExternal _
   |StmtEmpty ->
      state, stmt
   | StmtWhile (cond, stmts, attr) ->
      let state', stmts' = map_stmt mapper state stmts in
      state', StmtWhile (cond, stmts', attr)
   | StmtIf (cond, then_, Some else_, attr) ->
      let state', then_' = map_stmt mapper state then_ in
      let state', else_' = map_stmt mapper state' else_ in
      state', StmtIf (cond, then_', Some else_', attr)
   | StmtIf (cond, then_, None, attr) ->
      let state', then_' = map_stmt mapper state then_ in
      state', StmtIf (cond, then_', None, attr)
   | StmtFun (name, args, body, ret, attr) ->
      let state', body' = map_stmt mapper state body in
      state', StmtFun (name, args, body', ret, attr)
   | StmtBlock (name, stmts, attr) ->
      let state', stmts' = map_stmt_list mapper state stmts in
      state', StmtBlock (name, stmts', attr)


(** Applies a mapper to an expression that can collect statements *)
let map_exp_to_stmt (mapper : 'state mapper) (state : 'a Env.t) (exp : exp) : 'a Env.t * exp =
   let state', exp' = map_exp mapper state exp in
   state', exp'
