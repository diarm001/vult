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
open Prog
open Util
module Map = CCMap.Make (String)

type env =
  { functions : int Map.t
  ; locals : int Map.t
  ; lcount : int
  ; fcount : int
  }

let default_env = { locals = Map.empty; lcount = 0; functions = Map.empty; fcount = 0 }

let addLocal env name = { env with locals = Map.add name env.lcount env.locals; lcount = env.lcount + 1 }

type op =
  | OpAdd
  | OpSub
  | OpDiv
  | OpMul
  | OpMod
  | OpLand
  | OpLor
  | OpBor
  | OpBand
  | OpBxor
  | OpLsh
  | OpRsh
  | OpEq
  | OpNe
  | OpLt
  | OpLe
  | OpGt
  | OpGe

type rvalue_d =
  | RVoid
  | RInt    of int
  | RReal   of float
  | RBool   of bool
  | RString of string
  | RRef    of int
  | RObject of rvalue array
  | ROp     of op * rvalue * rvalue
  | RNot    of rvalue
  | RNeg    of rvalue
  | RIf     of rvalue * rvalue * rvalue
  | RMember of rvalue * int
  | RCall   of int * rvalue list
  | RIndex  of rvalue * rvalue

and rvalue =
  { r : rvalue_d
  ; t : type_
  ; loc : Loc.t
  }

type lvalue_d =
  | LVoid
  | LRef    of int
  | LTuple  of lvalue array
  | LMember of lvalue * int
  | LIndex  of lvalue * rvalue

and lvalue =
  { l : lvalue_d
  ; t : type_
  ; loc : Loc.t
  }

type instr_d =
  | Store  of lvalue * rvalue
  | Return of rvalue
  | If     of rvalue * instr list * instr list
  | While  of rvalue * instr list

and instr =
  { i : instr_d
  ; loc : Loc.t
  }

type segment =
  | External
  | Function of
      { name : string
      ; body : instr list
      ; locals : int
      ; index : int
      ; outputs : int
      }

type compiled =
  { table : int Map.t
  ; code : segment array
  }

let rec print_rvalue r : Pla.t =
  match r.r with
  | RVoid -> Pla.string "()"
  | RInt n -> Pla.int n
  | RReal n -> Pla.float n
  | RBool v -> Pla.string (if v then "true" else "false")
  | RString s -> Pla.string_quoted s
  | RRef n -> {pla|ref(<#n#i>)|pla}
  | RObject elems ->
      let elems = Pla.map_sep Pla.commaspace print_rvalue (Array.to_list elems) in
      {pla|( <#elems#> )|pla}
  | _ -> Pla.string "Not a value"


(*
  | ROp     of op * rvalue * rvalue
  | RNot    of rvalue
  | RNeg    of rvalue
  | RIf     of rvalue * rvalue * rvalue
  | RTuple  of rvalue list
  | RArray  of rvalue array
  | RMember of rvalue * int
  | RCall   of int * rvalue list
  | RIndex  of rvalue * rvalue
  *)

module Compile = struct
  let list f (env : 'env) (l : 'e) =
    let env, i_rev =
      List.fold_left
        (fun (env, instr) d ->
          let env, i = f env d in
          env, i :: instr)
        (env, [])
        l
    in
    env, List.flatten (List.rev i_rev)


  let getIndex name elems =
    let rec loop elems index =
      match elems with
      | [] -> failwith "index not found"
      | (current, _, _) :: _ when current = name -> index
      | _ :: t -> loop t (index + 1)
    in
    loop elems 0


  let rec dexp_to_lexp (d : dexp) : lexp =
    let t = d.t in
    let loc = d.loc in
    match d.d with
    | DWild -> { l = LWild; t; loc }
    | DId (name, _) -> { l = LId name; t; loc }
    | DTuple l ->
        let l = List.map dexp_to_lexp l in
        { l = LTuple l; t; loc }


  let rec compile_dexp (env : env) d =
    match d.d with
    | DWild -> env
    | DId (name, _) -> addLocal env name
    | DTuple l -> List.fold_left compile_dexp env l


  let rec compile_lexp (env : env) (l : lexp) : lvalue =
    let loc = l.loc in
    let t = l.t in
    match l.l with
    | LWild -> { l = LVoid; t; loc }
    | LId name ->
        let index = Map.find name env.locals in
        { l = LRef index; t; loc }
    | LTuple l ->
        let l = List.map (compile_lexp env) l |> Array.of_list in
        { l = LTuple l; t; loc }
    | LMember (e, s) ->
        begin
          match e.t.t with
          | TStruct descr ->
              let index = getIndex s descr.members in
              let e = compile_lexp env e in
              { l = LMember (e, index); t; loc }
          | _ -> failwith "type error"
        end
    | LIndex { e; index } ->
        let e = compile_lexp env e in
        let index = compile_exp env index in
        { l = LIndex (e, index); t; loc }


  and compile_exp (env : env) e : rvalue =
    let loc = e.loc in
    let t = e.t in
    match e.e with
    | EUnit -> { r = RVoid; t; loc }
    | EBool v -> { r = RBool v; t; loc }
    | EInt v -> { r = RInt v; t; loc }
    | EReal v -> { r = RReal v; t; loc }
    | EString v -> { r = RString v; t; loc }
    | EId id ->
        let index = Map.find id env.locals in
        { r = RRef index; t; loc }
    | EOp (op, e1, e2) ->
        let e1 = compile_exp env e1 in
        let e2 = compile_exp env e2 in
        { r = makeOp op e1 e2; t; loc }
    | EIndex { e; index } ->
        let e1 = compile_exp env e in
        let e2 = compile_exp env index in
        { r = RIndex (e1, e2); t; loc }
    | EUnOp (UOpNeg, e) ->
        let e = compile_exp env e in
        { r = RNeg e; t; loc }
    | EUnOp (UOpNot, e) ->
        let e = compile_exp env e in
        { r = RNot e; t; loc }
    | EIf { cond; then_; else_ } ->
        let cond = compile_exp env cond in
        let then_ = compile_exp env then_ in
        let else_ = compile_exp env else_ in
        { r = RIf (cond, then_, else_); t; loc }
    | ETuple elems ->
        let elems = List.map (compile_exp env) elems in
        { r = RObject (Array.of_list elems); t; loc }
    | EArray elems ->
        let elems = List.map (compile_exp env) elems in
        { r = RObject (Array.of_list elems); t; loc }
    | EMember (e, m) ->
        begin
          match e.t.t with
          | TStruct descr ->
              let index = getIndex m descr.members in
              let e = compile_exp env e in
              { r = RMember (e, index); t; loc }
          | _ -> failwith "type error"
        end
    | ECall { path; args } ->
        let args = List.map (compile_exp env) args in
        ( match Map.find_opt path env.functions with
        | Some index -> { r = RCall (index, args); t; loc }
        | None ->
            print_endline ("Function not found " ^ path) ;
            { r = RVoid; t; loc } )


  and makeOp op e1 e2 =
    match op with
    | OpAdd -> ROp (OpAdd, e1, e2)
    | OpSub -> ROp (OpAdd, e1, e2)
    | OpMul -> ROp (OpMul, e1, e2)
    | OpDiv -> ROp (OpDiv, e1, e2)
    | OpMod -> ROp (OpMod, e1, e2)
    | OpLand -> ROp (OpLand, e1, e2)
    | OpLor -> ROp (OpLor, e1, e2)
    | OpBor -> ROp (OpBor, e1, e2)
    | OpBand -> ROp (OpBand, e1, e2)
    | OpBxor -> ROp (OpBxor, e1, e2)
    | OpLsh -> ROp (OpLsh, e1, e2)
    | OpRsh -> ROp (OpRsh, e1, e2)
    | OpEq -> ROp (OpEq, e1, e2)
    | OpNe -> ROp (OpNe, e1, e2)
    | OpLt -> ROp (OpLt, e1, e2)
    | OpLe -> ROp (OpLe, e1, e2)
    | OpGt -> ROp (OpGt, e1, e2)
    | OpGe -> ROp (OpGe, e1, e2)


  let rec compile_stmt (env : env) (stmt : stmt) =
    let loc = stmt.loc in
    match stmt.s with
    | StmtDecl lhs ->
        let env = compile_dexp env lhs in
        env, []
    | StmtBind (lhs, rhs) ->
        let lhs = compile_lexp env lhs in
        let rhs = compile_exp env rhs in
        env, [ { i = Store (lhs, rhs); loc } ]
    | StmtReturn e ->
        let e = compile_exp env e in
        env, [ { i = Return e; loc } ]
    | StmtBlock stmts ->
        let env, instr = list compile_stmt env stmts in
        env, instr
    | StmtIf (cond, then_, Some else_) ->
        let cond = compile_exp env cond in
        let env, then_ = compile_stmt env then_ in
        let env, else_ = compile_stmt env else_ in
        env, [ { i = If (cond, then_, else_); loc } ]
    | StmtIf (cond, then_, None) ->
        let cond = compile_exp env cond in
        let env, then_ = compile_stmt env then_ in
        env, [ { i = If (cond, then_, []); loc } ]
    | StmtWhile (cond, body) ->
        let cond = compile_exp env cond in
        let env, body = compile_stmt env body in
        env, [ { i = While (cond, body); loc } ]


  let getNOutputs (t : type_) =
    match t.t with
    | TVoid
     |TInt
     |TReal
     |TString
     |TBool
     |TFixed
     |TArray _
     |TStruct _ ->
        1
    | TTuple elems -> List.length elems


  let compile_top (env : env) (s : top_stmt) =
    match s.top with
    | TopExternal ({ name; _ }, _) ->
        let index = env.fcount in
        let functions = Map.add name index env.functions in
        let env = { env with functions; fcount = env.fcount + 1 } in
        env, [ External ]
    | TopType _ -> env, []
    | TopFunction ({ name; args; t = _, ret; _ }, body) ->
        let index = env.fcount in
        let functions = Map.add name index env.functions in
        let env = { locals = Map.empty; lcount = 0; functions; fcount = env.fcount + 1 } in
        let env = List.fold_left (fun env (n, _, _) -> addLocal env n) env args in
        let env, body = compile_stmt env body in
        let outputs = getNOutputs ret in
        env, [ Function { name; body; locals = env.lcount; index; outputs } ]


  let compile stmts = list compile_top default_env stmts
end

module Eval = struct
  type vm =
    { stack : rvalue array
    ; mutable sp : int
    ; mutable frame : int
    ; table : int Map.t
    ; code : segment array
    }

  let new_vm (compiled : compiled) =
    { stack = Array.init 1024 (fun _ -> { r = RVoid; t = { t = TVoid; loc = Loc.default }; loc = Loc.default })
    ; sp = 0
    ; frame = 0
    ; table = compiled.table
    ; code = compiled.code
    }


  let numeric i f e1 e2 : rvalue_d =
    match e1.r, e2.r with
    | RInt n1, RInt n2 -> RInt (i n1 n2)
    | RReal n1, RReal n2 -> RReal (f n1 n2)
    | _ -> failwith "numeric: argument mismatch"


  let relation i f e1 e2 : rvalue_d =
    match e1.r, e2.r with
    | RInt n1, RInt n2 -> RBool (i n1 n2)
    | RReal n1, RReal n2 -> RBool (f n1 n2)
    | _ -> failwith "relation: argument mismatch"


  let logic f e1 e2 : rvalue_d =
    match e1.r, e2.r with
    | RBool n1, RBool n2 -> RBool (f n1 n2)
    | _ -> failwith "logic: argument mismatch"


  let bitwise f e1 e2 : rvalue_d =
    match e1.r, e2.r with
    | RInt n1, RInt n2 -> RInt (f n1 n2)
    | _ -> failwith "bitwise: argument mismatch"


  let not e : rvalue_d =
    match e.r with
    | RInt n -> RInt (lnot n)
    | RBool n -> RBool (not n)
    | _ -> failwith "not: argument mismatch"


  let neg e : rvalue_d =
    match e.r with
    | RInt n -> RInt (-n)
    | RReal n -> RReal (-.n)
    | _ -> failwith "not: argument mismatch"


  let push (vm : vm) (value : rvalue) =
    vm.sp <- vm.sp + 1 ;
    vm.stack.(vm.sp) <- value


  let pop (vm : vm) : rvalue =
    let ret = vm.stack.(vm.sp) in
    vm.sp <- vm.sp - 1 ;
    ret


  let loadRef (vm : vm) n : rvalue = vm.stack.(vm.frame + n)

  let storeRef (vm : vm) n v = vm.stack.(vm.frame + n) <- v

  let storeRefObject (vm : vm) n i v =
    match vm.stack.(vm.frame + n) with
    | { r = RObject elems; _ } -> elems.(i) <- v
    | _ -> failwith "storeRefMember: invalid input"


  let pushArgs (vm : vm) (args : rvalue list) = List.iter (fun v -> push vm v) args

  let allocate (vm : vm) n = vm.sp <- vm.sp + n

  let eval_op (op : op) =
    match op with
    | OpAdd -> numeric ( + ) ( +. )
    | OpSub -> numeric ( - ) ( -. )
    | OpDiv -> numeric ( / ) ( /. )
    | OpMul -> numeric ( * ) ( *. )
    | OpMod -> numeric ( mod ) mod_float
    | OpEq -> relation ( = ) ( = )
    | OpNe -> relation ( <> ) ( <> )
    | OpLt -> relation ( < ) ( < )
    | OpGt -> relation ( > ) ( > )
    | OpLe -> relation ( <= ) ( <= )
    | OpGe -> relation ( >= ) ( >= )
    | OpLand -> logic ( && )
    | OpLor -> logic ( || )
    | OpBor -> bitwise ( lor )
    | OpBand -> bitwise ( land )
    | OpBxor -> bitwise ( lxor )
    | OpLsh -> bitwise ( lsl )
    | OpRsh -> bitwise ( lsr )


  let isTrue (cond : rvalue) =
    match cond with
    | { r = RBool true; _ } -> true
    | { r = RBool false; _ } -> false
    | _ -> failwith "invalid condition"


  let rec eval_rvalue (vm : vm) (r : rvalue) : rvalue =
    match r.r with
    | RVoid
     |RInt _
     |RReal _
     |RBool _
     |RString _ ->
        r
    | RRef n -> loadRef vm n
    | ROp (op, e1, e2) ->
        let e1 = eval_rvalue vm e1 in
        let e2 = eval_rvalue vm e2 in
        { r with r = (eval_op op) e1 e2 }
    | RNeg e ->
        let e = eval_rvalue vm e in
        { r with r = neg e }
    | RNot e ->
        let e = eval_rvalue vm e in
        { r with r = not e }
    | RIf (cond, then_, else_) ->
        let cond = eval_rvalue vm cond in
        begin
          match cond.r with
          | RBool true -> eval_rvalue vm then_
          | RBool false -> eval_rvalue vm else_
          | _ -> failwith "invaid if-condition"
        end
    | RObject elems ->
        let elems = Array.map (eval_rvalue vm) elems in
        { r with r = RObject elems }
    | RIndex (e, index) ->
        let e = eval_rvalue vm e in
        let index = eval_rvalue vm index in
        begin
          match e, index with
          | { r = RObject elems; _ }, { r = RInt index; _ } -> elems.(index)
          | _ -> failwith "index not evaluated correctly"
        end
    | RCall (index, args) ->
        let args = List.map (eval_rvalue vm) args in
        eval_call vm index args
    | RMember (e, index) ->
        let e = eval_rvalue vm e in
        begin
          match e.r with
          | RObject elems -> elems.(index)
          | _ -> failwith "not a struct"
        end


  and eval_lvalue (vm : vm) (l : lvalue) : lvalue =
    match l.l with
    | LVoid -> l
    | LRef _ -> l
    | LTuple elems ->
        let elems = Array.map (eval_lvalue vm) elems in
        { l with l = LTuple elems }
    | LMember (e, m) ->
        let e = eval_lvalue vm e in
        { l with l = LMember (e, m) }
    | LIndex (e, i) ->
        let e = eval_lvalue vm e in
        let i = eval_rvalue vm i in
        { l with l = LIndex (e, i) }


  and eval_call (vm : vm) findex (args : rvalue list) =
    match vm.code.(findex) with
    | Function { body; locals; _ } ->
        vm.frame <- vm.sp + 1 ;
        pushArgs vm args ;
        allocate vm locals ;
        eval_instr vm body ;
        let ret = pop vm in
        vm.sp <- vm.frame ;
        ret
    | External -> failwith ""


  and eval_instr (vm : vm) (instr : instr list) =
    match instr with
    | [] -> ()
    | { i = Return e; _ } :: _ ->
        let e = eval_rvalue vm e in
        push vm e
    | { i = If (cond, then_, else_); _ } :: t ->
        let cond = eval_rvalue vm cond in
        if isTrue cond then
          let () = eval_instr vm then_ in
          eval_instr vm t
        else
          let () = eval_instr vm else_ in
          eval_instr vm t
    | { i = While (cond, body); _ } :: t ->
        let rec loop () =
          let result = eval_rvalue vm cond in
          if isTrue result then
            let () = eval_instr vm body in
            loop ()
          else
            eval_instr vm t
        in
        loop ()
    | { i = Store (l, r); _ } :: t ->
        let l = eval_lvalue vm l in
        let r = eval_rvalue vm r in
        store vm l r ;
        eval_instr vm t


  and store (vm : vm) (l : lvalue) (r : rvalue) =
    match l.l, r.r with
    | LVoid, _ -> ()
    | LRef n, _ -> storeRef vm n r
    | LMember ({ l = LRef n; _ }, m), _ -> storeRefObject vm n m r
    | LIndex ({ l = LRef n; _ }, { r = RInt i; _ }), _ -> storeRefObject vm n i r
    | LTuple l_elems, RObject r_elems -> Array.iter2 (store vm) l_elems r_elems
    | _ -> failwith "invalid store"
end

let compile stmts =
  let env, functions = Compile.compile stmts in
  { table = env.functions; code = Array.of_list functions }


let run (env : Env.in_top) (prog : top_stmt list) (exp : string) =
  let wrapper = Pla.print {pla| fun _main_() return <#exp#s>; |pla} in
  let e = Parser.Parse.parseString (Some "Main_.vult") wrapper in
  let env, stmts = Inference.infer_single env e in
  let stmts = Prog.convert env stmts in
  let compiled = compile (prog @ stmts) in
  let vm = Eval.new_vm compiled in
  let findex = Map.find "Main___main_" vm.table in
  let result = Eval.eval_call vm findex [] in
  let str = Pla.print (print_rvalue result) in
  str
