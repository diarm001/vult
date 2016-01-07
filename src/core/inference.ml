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

This code is based on the type inference examples provided in:
   http://okmij.org/ftp/ML/generalization.html

*)

open TypesVult
open VEnv
open Common


let expLoc e = lazy (GetLocation.fromExp e)
let lhsLoc e = lazy (GetLocation.fromLhsExp e)
let expOptLoc e =
   lazy (
   match e with
   | None -> Loc.default
   | Some(e) -> GetLocation.fromExp e)


let unifyRaise (loc:Loc.t Lazy.t) (t1:VType.t) (t2:VType.t) : unit =
   let raise = true in
   if not (VType.unify t1 t2) then
      let msg = Printf.sprintf "This expression has type '%s' but '%s' was expected" (PrintTypes.typeStr t2) (PrintTypes.typeStr t1) in
      if raise then
         Error.raiseError msg (Lazy.force loc)
      else
         begin
            print_endline (Loc.to_string (Lazy.force loc));
            print_endline msg
         end

let rec unifyListSameType (args:exp list) (types:VType.t list) (common_type:VType.t) =
   match args, types with
   | [],[] -> common_type
   | arg::args, typ::types ->
      unifyRaise (expLoc arg) typ common_type;
      unifyListSameType args types common_type
   | _ -> raise (Invalid_argument "unifyListSameType")


let rec inferLhsExp (env:'a Env.t) (e:lhs_exp) : lhs_exp * VType.t =
   match e with
   | LWild(attr) ->
      let typ = VType.newvar () in
      LWild( { attr with typ = Some(typ) }), typ
   | LId(id,None,attr) ->
      let typ = try Env.lookup `Variable env id |> snd with | _ -> VType.newvar () in
      LId(id,Some(typ),{ attr with typ = Some(typ) }), typ
   | LId(id,Some(typ),attr) ->
      LId(id,Some(typ),{ attr with typ = Some(typ) }), typ
   | LTuple(elems,attr) ->
      let elems',tpl =
         List.fold_left (fun (elems,tpl) a ->
            let a',typ = inferLhsExp env a in
            a' :: elems, typ :: tpl )
         ([],[])
         elems
      in
      let typ = ref (VType.TComposed(["tuple"],List.rev tpl,None)) in
      LTuple(List.rev elems',attr),typ
   | LTyped(e,typ,_) ->
      let e',tpi = inferLhsExp env e in
      unifyRaise (lhsLoc e) typ tpi;
      e',tpi

let rec addLhsToEnv mem_var (env:'a Env.t) (lhs:lhs_exp) : 'a Env.t =
   match lhs with
   | LWild _ -> env
   | LId(id,Some(typ),_) ->
      if mem_var = `Mem then Env.addMem env id typ else Env.addVar env id typ
   | LId(_,None,_) -> env
   | LTuple(elems,_) ->
      List.fold_left (fun e a -> addLhsToEnv mem_var e a) env elems
   | LTyped(e,_,_) ->
      addLhsToEnv mem_var env e

let rec addArgsToEnv (env:'a Env.t) (args:typed_id list) : typed_id list * VType.t list * 'a Env.t =
   match args with
   | [] -> [], [], env
   | SimpleId(id,attr)::t ->
      let typ  = VType.newvar () in
      let env' = Env.addVar env id typ in
      let inner_args, inner_typ, env' = addArgsToEnv env' t in
      TypedId(id,typ,attr) :: inner_args, typ :: inner_typ, env'
   | TypedId(id,typ,attr)::t ->
      let env' = Env.addVar env id typ in
      let inner_args, inner_typ, env' = addArgsToEnv env' t in
      TypedId(id,typ,attr) :: inner_args, typ :: inner_typ, env'


let unifyOpt (loc:Loc.t Lazy.t) (typ1:VType.t option) (typ2:VType.t option) : VType.t option =
   match typ1,typ2 with
   | None, None    -> None
   | Some(_), None -> typ1
   | None, Some(_) -> typ2
   | Some(t1), Some(t2) ->
      unifyRaise loc t1 t2;
      typ1

let getOptType (typ:VType.t option) : VType.t =
   match typ with
   | None    -> VType.newvar ()
   | Some(t) -> t


let inferApplyArgCount (loc:Loc.t Lazy.t) (args_typ:VType.t list) (fn_args:VType.t list) : unit =
   let n_args    = List.length args_typ in
   let n_fn_args = List.length fn_args in
   if  n_args <> n_fn_args then
      Error.raiseError (Printf.sprintf "This function takes %i arguments but %i are passed" n_fn_args n_args) (Lazy.force loc)

let rec inferApplyArg (args:exp list) (args_typ:VType.t list) (fn_args:VType.t list) : unit =
   match args, args_typ, fn_args with
   | [], [], [] -> ()
   | arg::args, arg_typ::args_typ, fn_arg::fn_args ->
      unifyRaise (expLoc arg) fn_arg arg_typ;
      inferApplyArg args args_typ fn_args
   | _ -> failwith "Inference.inferApplyArg: invalid input"

let inferApply (loc:Loc.t Lazy.t) (args:exp list) (args_typ:VType.t list) (ret_type:VType.t) (fn_args:VType.t list) (fn_ret_type:VType.t) =
   inferApplyArgCount loc args_typ fn_args;
   inferApplyArg args args_typ fn_args;
   unifyRaise loc fn_ret_type ret_type


let rec inferExp (env:'a Env.t) (e:exp) : exp * VType.t =
   match e with
   | PUnit(attr) ->
      PUnit({ attr with typ = Some(VType.Constants.unit_type) }), VType.Constants.unit_type
   | PBool(v,attr) ->
      PBool(v,{ attr with typ = Some(VType.Constants.bool_type) }), VType.Constants.bool_type
   | PInt(v,attr) ->
      let typ = VType.Constants.int_type in
      PInt(v,{ attr with typ = Some(typ) }), typ
   | PReal(v,attr) ->
      PReal(v,{ attr with typ = Some(VType.Constants.real_type) }), VType.Constants.real_type
   | PId(id,attr) ->
      let typ = try Env.lookup `Variable env id |> snd with | _ -> failwith ("Undefined symbol '" ^ (PrintTypes.identifierStr id)^"'") in
      PId(id, { attr with typ = Some(typ) }), typ
   | PGroup(e,_) ->
      inferExp env e
   | PTuple(elems,attr) ->
      let elems', types = inferExpList env elems in
      let typ           = ref (VType.TComposed(["tuple"],types,None)) in
      PTuple(elems',{ attr with typ = Some(typ) }), typ
   | PIf(cond,then_,else_,attr) ->
      let cond',cond_type  = inferExp env cond in
      let then_',then_type = inferExp env then_ in
      let else_',else_type = inferExp env else_ in
      unifyRaise (expLoc cond') (VType.Constants.bool_type) cond_type;
      unifyRaise (expLoc else_') then_type else_type;
      PIf(cond',then_',else_',{ attr with typ = Some(then_type) }), then_type
   | PCall(name,fname,args,attr) ->
      let args',types = inferExpList env args in
      let ret_type    = VType.newvar () in
      let _, fn_type  = Env.lookup `Function env fname in
      let fn_args,fn_ret = VType.stripArrow fn_type in
      inferApply (expLoc e) args' types ret_type fn_args fn_ret;
      PCall(name,fname,args',{ attr with typ = Some(ret_type) }), ret_type
   | POp(op,[e1;e2],attr) ->
      let e1',e1_typ  = inferExp env e1 in
      let e2',e2_typ  = inferExp env e2 in
      let ret_type    = VType.newvar () in
      let _, fn_type  = Env.lookup `Operator env [op] in
      let fn_args,fn_ret = VType.stripArrow fn_type in
      inferApply (expLoc e) [e1'; e2'] [e1_typ; e2_typ] ret_type fn_args fn_ret;
      POp(op,[e1';e2'],{ attr with typ = Some(ret_type) }), ret_type
   | POp(op,args,attr) ->
      let args',types = inferExpList env args in
      let _, fn_type  = Env.lookup `Operator env [op] in
      let common_type =
         match VType.stripArrow fn_type with
         | [arg1;arg2], ret ->
            if VType.unify arg1 arg2 && VType.unify arg2 ret then
               ret
            else
               failwith "The operator cannot be used with multiple arguments"
         | _ -> failwith "The operator cannot be used with multiple arguments"
      in
      let ret_type = unifyListSameType args' types common_type in
      POp(op,args',{ attr with typ = Some(ret_type) }), ret_type
   | PUnOp(op,arg,attr) ->
      let arg',arg_type = inferExp env arg in
      let ret_type      = VType.newvar () in
      let _, fn_type    = Env.lookup `Operator env ["|"^op^"|"] in
      let fn_args,fn_ret = VType.stripArrow fn_type in
      inferApply (expLoc e) [arg'] [arg_type] ret_type fn_args fn_ret;
      PUnOp(op,arg',{ attr with typ = Some(ret_type) }), ret_type
   | PSeq(name,stmt,attr) ->
      let stmt', _, ret_type = inferStmt env None stmt in
      let typ = getOptType ret_type in
      PSeq(name,stmt',{ attr with typ = Some(typ)}), typ
   | PEmpty -> PEmpty, VType.Constants.unit_type

and inferExpList (env:'a Env.t) (elems:exp list) : exp list * VType.t list =
   let elems',types =
      List.fold_left (fun (elems,types) a ->
         let a',typ = inferExp env a in
         a' :: elems, typ :: types )
      ([],[])
      elems
   in List.rev elems', List.rev types

and inferOptExp (env:'a Env.t) (e:exp option) : exp option * VType.t =
   match e with
   | None    -> None, VType.newvar ()
   | Some(e) ->
      let e',typ = inferExp env e in
      Some(e'), typ

and inferStmt (env:'a Env.t) (ret_type:VType.t option) (stmt:stmt) : stmt * 'a Env.t * VType.t option =
   match stmt with
   | StmtVal(lhs,rhs,attr) ->
      let lhs', lhs_typ = inferLhsExp env lhs in
      let rhs', rhs_typ = inferOptExp env rhs in
      unifyRaise (expOptLoc rhs) lhs_typ rhs_typ;
      let env' = addLhsToEnv `Var env lhs' in
      StmtVal(lhs', rhs', attr), env', ret_type
   | StmtMem(lhs,init,rhs,attr) ->
      let lhs', lhs_typ   = inferLhsExp env lhs in
      let env'            = addLhsToEnv `Mem env lhs' in
      let init', init_typ = inferOptExp env' init in
      let rhs', rhs_typ   = inferOptExp env' rhs in
      unifyRaise (expOptLoc init') lhs_typ init_typ;
      unifyRaise (expOptLoc rhs') lhs_typ rhs_typ;
      StmtMem(lhs', init', rhs', attr), env', ret_type
   | StmtTable(id,elems,attr) ->
      let elems',types = inferExpList env elems in
      let typ = unifyListSameType elems' types (VType.newvar ()) in
      let env' = Env.addVar env id typ in
      StmtTable(id,elems',attr), env', ret_type
   | StmtReturn(e,attr) ->
      let e', typ   = inferExp env e in
      let ret_type' = unifyOpt (expLoc e) ret_type (Some(typ)) in
      StmtReturn(e',attr), env, ret_type'
   | StmtBind(lhs,rhs,attr) ->
      let lhs', lhs_typ = inferLhsExp env lhs in
      let rhs', rhs_typ = inferExp env rhs in
      unifyRaise (expLoc rhs') lhs_typ rhs_typ;
      StmtBind(lhs',rhs',attr), env, ret_type
   | StmtBlock(name,stmts,attr) ->
      let env' = Env.enter `Block env [] in
      let stmts', env', stmt_ret_type = inferStmtList env' ret_type stmts in
      let env' = Env.exit `Block env' in
      StmtBlock(name,stmts',attr), env', stmt_ret_type
   | StmtFun(name,args,body,ret_type,attr) ->
      VType.enterLevel ();
      let env' =
         Env.enter `Function env name
         |> Env.prepareContext attr.fun_and
      in
      let args', types, env'  = addArgsToEnv env' args in
      let types',table = VType.fixTypeList [] types in
      let ret_type',_ = VType.fixOptType table ret_type in
      let body',env',body_ret = inferStmt env' ret_type' body in
      let last_type = getOptType body_ret in
      let typ  = VType.makeArrowType last_type types' in
      let env' = Env.setCurrentType env' typ true in
      let env' = Env.exit `Function env' in
      VType.leaveLevel ();
      StmtFun(name,args',body',body_ret,attr), env', None
   | StmtIf(cond,then_,else_,attr) ->
      let cond', cond_type  = inferExp env cond in
      unifyRaise (expLoc cond') (VType.Constants.bool_type) cond_type;
      let then_', env', ret_type' = inferStmt env ret_type then_ in
      let else_', env', ret_type' = inferOptStmt env' ret_type' else_ in
      StmtIf(cond',then_',else_',attr), env', ret_type'
   | StmtWhile(cond,body,attr) ->
      let cond', cond_type  = inferExp env cond in
      unifyRaise (expLoc cond') (VType.Constants.bool_type) cond_type;
      let body', env', ret_type' = inferStmt env ret_type body in
      StmtWhile(cond',body',attr), env', ret_type'
   | StmtType(name,args,members,attr) ->
      StmtType(name,args,members,attr), env, ret_type
   | StmtAliasType (name, args, alias, attr) ->
      StmtAliasType (name, args, alias, attr), env, ret_type
   | StmtExternal(name,args,fun_ret_type,attr) ->
      let env' = Env.enter `Function env name in
      let args',types, env' = addArgsToEnv env' args in
      let typ  = VType.makeArrowType fun_ret_type types in
      let env' = Env.setCurrentType env' typ true in
      let env' = Env.exit `Function env' in
      StmtExternal(name,args',fun_ret_type,attr), env', ret_type
   | StmtEmpty -> StmtEmpty, env, ret_type


and inferStmtList (env:'a Env.t) (ret_type_in:VType.t option) (stmts:stmt list) : stmt list * 'a Env.t * VType.t option =
   let stmts', env', ret_type' =
      List.fold_left
         (fun (stmts,env,ret_type) stmt ->
            let stmt', env', ret_type' = inferStmt env ret_type stmt in
            stmt' :: stmts, env', ret_type')
         ([], env, ret_type_in)
         stmts
   in (List.rev stmts'), env', ret_type'

and inferOptStmt (env:'a Env.t) (ret_type:VType.t option) (stmt:stmt option) : stmt option * 'a Env.t * VType.t option =
   match stmt with
   | None -> None, env, ret_type
   | Some(s) ->
      let s', s_type,s_ret_type = inferStmt env ret_type s in
      Some(s'), s_type, s_ret_type
