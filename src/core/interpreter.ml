(*
   The MIT License (MIT)

   Copyright (c) 2016 Leonardo Laguna Ruiz, Carl Jönsson

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
open Common

(*
   type value =
   | Unit
   | Int of int
   | Bool of bool
   | Real of float
   | String of string
   | Array of value array
   | Tuple of value list

   type ienv =
   {
   mutable ctx_values : (Id.t * int) list;
   mutable locals : (Id.t * int) list list;
   }

   type ctx =
   {
   mem : value array;
   locals : value array;
   }

   let findInCtx (env:ienv) (name:Id.t) : int option =
   CCList.assoc_opt name env.ctx_values

   let findInLocal (env:ienv) (name:Id.t) : int option =
   let rec loop locals =
   match locals with
   | [] -> None
   | h :: t ->
   match CCList.assoc_opt name h with
   | Some _  as result -> result
   | _ -> loop t
   in
   loop env.locals

   let findVar (env:ienv) (name:Id.t) : int option =
   match findInCtx env name with
   | Some _  as result -> result
   | _ -> findInLocal env name

   let getValue ctx i =
   if i > 1000 then Array.get ctx.locals (i - 1000)
   else Array.get ctx.mem i

   let getArrayValue v i =
   match v, i with
   | Array a, Int index -> Array.get a index
   | _ -> failwith "getArrayValue"

   let applyOp (op:string) (e1:value) (e2:value) : value =
   match op, e1, e2 with
   | "+", Real(v1), Real(v2)  -> Real(v1 +. v2)
   | "+", Int(v1),  Int(v2)   -> Int(v1 + v2)
   | "-", Real(v1), Real(v2)  -> Real(v1 -. v2)
   | "-", Int(v1),  Int(v2 )   -> Int(v1 - v2)
   | "*", Real(v1), Real(v2)  -> Real(v1 *. v2)
   | "*", Int(v1),  Int(v2)   -> Int(v1 * v2)
   | "/", Real(v1), Real(v2)  -> Real(v1  /. v2)
   | "/", Int(v1),  Int(v2)    -> Int(v1 / v2)
   | "%", Real(v1), Real(v2)  -> Real(mod_float  v1  v2)
   | "%", Int(v1),  Int(v2)   -> Int(v1 mod v2)
   | "==", Real(v1), Real(v2) -> Bool(v1 = v2)
   | "==", Int(v1),  Int(v2)  -> Bool(v1 = v2)
   | "<>", Real(v1), Real(v2) -> Bool(v1 <> v2)
   | "<>", Int(v1),  Int(v2)  -> Bool(v1 <> v2)
   | ">", Real(v1), Real(v2)  -> Bool(v1 > v2)
   | ">", Int(v1),  Int(v2)   -> Bool(v1 > v2)
   | "<", Real(v1), Real(v2)  -> Bool(v1 < v2)
   | "<", Int(v1),  Int(v2)   -> Bool(v1 < v2)
   | ">=", Real(v1), Real(v2) -> Bool(v1 >= v2)
   | ">=", Int(v1),  Int(v2)  -> Bool(v1 >= v2)
   | "<=", Real(v1), Real(v2) -> Bool(v1 <= v2)
   | "<=", Int(v1),  Int(v2)  -> Bool(v1 <= v2)
   | "&&", Bool(v1),  Bool(v2)  -> Bool(v1 && v2)
   | "||", Bool(v1),  Bool(v2)  -> Bool(v1 || v2)
   | _ -> failwith "invalid operation"

   let applyUnOp (op:string) (e1:value) : value =
   match op, e1 with
   | "-", Real(v) -> Real(-. v)
   | "-", Int(v) -> Int(- v)
   | _ -> failwith "invalid unary operation"

   let foldOperations op args =
   match args with
   | [] -> failwith "no arguments"
   | [s; a] -> applyOp op s a
   | h :: t ->
   List.fold_left (fun s a -> applyOp op s a) h t

   let rec compileExp env exp =
   match exp with
   | PUnit _        -> (fun _ -> Unit)
   | PBool (v, _)   -> (fun _ -> Bool v)
   | PInt (v, _)    -> (fun _   -> Int v)
   | PReal (v, _)   -> (fun _ -> Real v)
   | PString (v, _) -> (fun _ -> String v)
   | PId (id, _)    ->
   begin match findVar env id with
   | Some i -> (fun ctx -> getValue ctx i)
   | None -> failwith "Cannot find variable"
   end
   | PIndex(v, i, _) ->
   let v = compileExp env v in
   let i = compileExp env i in
   (fun ctx -> getArrayValue (v ctx) (i ctx))

   | PArray(v, _) ->
   let v = Array.map (compileExp env) v in
   (fun ctx -> Array (Array.map (fun a -> a ctx) v))

   | PIf(cond, then_, else_, _) ->
   let cond = compileExp env cond in
   (fun ctx ->
   match cond ctx with
   | Bool true -> (compileExp env then_) ctx
   | Bool false -> (compileExp env else_) ctx
   | _ -> failwith "invalid if expression")


   | PGroup (e, _) -> compileExp env e
   | PTuple (e, _) ->
   let e = List.map (compileExp env) e in
   (fun ctx -> Tuple (List.map (fun a -> a ctx) e))

   | POp(op, args, _) ->
   let args = List.map (compileExp env) args in
   (fun ctx -> foldOperations op (List.map (fun a -> a ctx) args))

   | PUnOp(op, e, _) ->
   let e = compileExp env e in
   (fun ctx -> applyUnOp op (e ctx))

   | PCall(name, f, args , _) -> failwith ""

   | PEmpty -> failwith ""
   | PSeq _ -> failwith ""
*)

module SimpleMap = struct
   module IdMap = Map.Make (struct
         type t = Id.t

         let compare = Id.compare
      end)

   type 'value t = 'value IdMap.t ref

   let create (_size : int) : 'value t = ref IdMap.empty

   let[@inline always] mem (t : 'value t) (key : 'key) : bool = IdMap.mem key !t

   let[@inline always] find (t : 'value t) (key : 'key) : 'value = IdMap.find key !t

   let[@inline always] add (t : 'value t) (key : 'key) (value : 'value) : unit = t := IdMap.add key value !t

   let replace = add
end

module Env = struct
   type fun_body =
      | External
      | Declared of stmt
      | Builtin  of (attr -> exp list -> exp)

   type t =
      { locals : exp SimpleMap.t list
      ; context : exp SimpleMap.t
      ; instances : t SimpleMap.t
      ; functions : fun_body SimpleMap.t
      ; modules : t SimpleMap.t
      ; tick : int
      }

   type env = t list
   (** Non empty list of 't' *)

   let new_t () =
      { locals = [ SimpleMap.create 4 ]
      ; context = SimpleMap.create 4
      ; instances = SimpleMap.create 4
      ; functions = SimpleMap.create 4
      ; modules = SimpleMap.create 4
      ; tick = 0
      }


   let top () : env = [ new_t () ]

   (**  Returns the first environment *)
   let first (env : env) : t =
      match env with
      | t :: _ -> t
      | [] -> failwith "invalid env"


   (** Used by lookupFunction to iterate the environments until the function is found *)
   let rec lookupFunction_loop (t : t) (env : env) (id : Id.t) : (t * fun_body) option =
      match id with
      | [] -> None
      | name1 :: name2 ->
         if name2 = [] && SimpleMap.mem t.functions [ name1 ] then
            (* exists in the functions table and it's a single name *)
            Some (t, SimpleMap.find t.functions [ name1 ])
         else if name2 <> [] && SimpleMap.mem t.modules [ name1 ] then
            (* exists in the modules table and it is not a single name *)
            let t' = SimpleMap.find t.modules [ name1 ] in
            lookupFunction_loop t' env name2
         else (
            (* not found, go one level up *)
            match env with
            | t' :: env' -> lookupFunction_loop t' env' id
            | [] ->
               (* no more environments to look for *)
               None )


   (** Looks for a function with the given name *)
   let lookupFunction (env : env) (id : Id.t) : (t * fun_body) option =
      match env with
      | h :: t -> lookupFunction_loop h t id
      | [] -> failwith "invalid env"


   (** Used by lookupVar to iterate all local scopes *)
   let rec lookupVar_loop locals id : exp =
      match locals with
      | [] -> raise Not_found
      | h :: t ->
         match SimpleMap.find h id with
         | value -> value
         | exception Not_found -> lookupVar_loop t id


   let lookupVar (env : env) (id : Id.t) : exp =
      let t = first env in
      (* first try to find the variable in the context *)
      match SimpleMap.find t.context id with
      | value -> value
      | exception Not_found ->
         (* if is not in the context then look in the locals *)
         lookupVar_loop t.locals id


   (** Adds a mem variable to the context, if the variable exists, it does nothing *)
   let declareMem (env : env) (id : Id.t) (value : exp) : unit =
      match lookupVar env id with
      | _ -> ()
      | exception Not_found ->
         let t = first env in
         SimpleMap.add t.context id value


   (** Adds a local variable to the current scope, if the variable exists, it does nothing *)
   let declareVal (env : env) (id : Id.t) (value : exp) : unit =
      match lookupVar env id with
      | _ -> ()
      | exception Not_found ->
         let t = first env in
         ( match t.locals with
           | h :: _ -> SimpleMap.replace h id value
           | [] -> failwith "invalid env" )


   (** Used by updateVar to iterate all local scopes *)
   let rec updateVar_loop (locals : 'a list) (id : Id.t) (value : exp) : unit =
      match locals with
      | [] -> failwith ("unknow variable: " ^ PrintProg.identifierStr id)
      | h :: t ->
         match SimpleMap.mem h id with
         | _ -> SimpleMap.replace h id value
         | exception Not_found -> updateVar_loop t id value


   (** Looks for an existing variable and updates its value *)
   let updateVar (env : env) (id : Id.t) (value : exp) : unit =
      let t = first env in
      match SimpleMap.mem t.context id with
      | _ -> SimpleMap.replace t.context id value
      | exception Not_found -> updateVar_loop t.locals id value


   (** Used by updateArrayVar to iterate all local scopes *)
   let rec updateArrayVar_loop (locals : 'a list) (id : Id.t) (index : exp) (value : exp) : unit =
      match locals with
      | [] -> failwith ("unknow variable: " ^ PrintProg.identifierStr id)
      | h :: t ->
         match SimpleMap.find h id, index with
         | PArray (elems, _), PInt (index, _) -> elems.(index) <- value
         | _ -> failwith "cannot update array"
         | exception Not_found -> updateArrayVar_loop t id index value


   (** Looks for an existing variable and updates its value *)
   let updateArrayVar (env : env) (id : Id.t) (index : exp) (value : exp) : unit =
      let t = first env in
      match SimpleMap.find t.context id, index with
      | PArray (elems, _), PInt (index, _) -> elems.(index) <- value
      | _ -> failwith "cannot update array"
      | exception Not_found -> updateArrayVar_loop t.locals id index value


   (** Adds a function to the scope *)
   let addFunction env id (stmt : fun_body) =
      let t = first env in
      SimpleMap.add t.functions id stmt


   (** Adds a module to the scope *)
   let addModule (env : env) (id : Id.t) : unit =
      let t = first env in
      SimpleMap.add t.modules id (new_t ())


   (** Enters to the scope of a module *)
   let enterModule (env : env) (id : Id.t) : env =
      let t = first env in
      match SimpleMap.find t.modules id with
      | module_t -> module_t :: env
      | exception Not_found -> failwith ("unknown module: " ^ PrintProg.identifierStr id)


   (** Inserts a table to store local variables *)
   let enterLocal (env : env) : env =
      match env with
      | [ t ] ->
         let locals = SimpleMap.create 4 :: t.locals in
         let t' = { t with locals } in
         [ t' ]
      | t :: l ->
         let locals = SimpleMap.create 4 :: t.locals in
         let t' = { t with locals } in
         t' :: l
      | [] -> failwith "invalid env"


   (** Gets the context of a function call *)
   let enterInstance (env : env) (id : Id.t) : env =
      let t = first env in
      match SimpleMap.find t.instances id with
      | inst -> inst :: env
      | exception Not_found ->
         let inst = new_t () in
         SimpleMap.add t.instances id inst ;
         inst :: env
end

exception Abort

(** Constant unit value *)
let ret_unit = PUnit emptyAttr

(** Returns a context name for the a funtion call based on its location *)
let makeInstName (fn : Id.t) (attr : attr) : Id.t =
   let line = Loc.line attr.loc in
   let col = Loc.startColumn attr.loc in
   let n = string_of_int (line + col) in
   match fn with
   | [ id ] -> [ id ^ "_" ^ n ]
   | [ pack; id ] -> [ pack ^ "_" ^ id ^ "_" ^ n ]
   | _ -> failwith "invalid function name"


(** Returns the initial value given the type of an expression *)
let rec getInitValue (tp : Typ.t) : exp =
   match !tp with
   | Typ.TId ([ "unit" ], _) -> PUnit emptyAttr
   | Typ.TId ([ "real" ], _) -> PReal (0.0, Float, emptyAttr)
   | Typ.TId ([ "fix16" ], _) -> PReal (0.0, Fix16, emptyAttr)
   | Typ.TId ([ "int" ], _) -> PInt (0, emptyAttr)
   | Typ.TId ([ "abstract" ], _) -> PInt (0, emptyAttr)
   | Typ.TId ([ "bool" ], _) -> PBool (false, emptyAttr)
   | Typ.TComposed ([ "array" ], [ sub; { contents = Typ.TInt (size, _) } ], _) ->
      let sub_init = getInitValue sub in
      let elems = Array.init size (fun _ -> sub_init) in
      PArray (elems, emptyAttr)
   | Typ.TComposed ([ "tuple" ], types, _) ->
      let elems = List.map getInitValue types in
      PTuple (elems, emptyAttr)
   | Typ.TLink tp -> getInitValue tp
   | _ -> failwith "Interpreter.getInitValue"


(** Returns the initial value given the lhs expression *)
let getInitExp (lhs : lhs_exp) : exp =
   match (GetAttr.fromLhsExp lhs).typ with
   | Some typ -> getInitValue typ
   | None -> failwith ("Interpreter.getInitExp: cannot get the initial expression: " ^ PrintProg.lhsExpressionStr lhs)


(** Evaluates unary operations *)
let evalUop (op : string) (exp : exp) : exp =
   match op, exp with
   | "-", PInt (v, attr) -> PInt (-v, attr)
   | "-", PReal (v, precision, attr) -> PReal (-.v, precision, attr)
   | _ -> PUnOp (op, exp, emptyAttr)


(** Evaluates binary operations *)
let evalOp (op : string) (e1 : exp) (e2 : exp) : exp =
   match op, e1, e2 with
   | "+", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PReal (v1 +. v2, p1, attr)
   | "+", PInt (v1, attr), PInt (v2, _) -> PInt (v1 + v2, attr)
   | "-", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PReal (v1 -. v2, p1, attr)
   | "-", PInt (v1, attr), PInt (v2, _) -> PInt (v1 - v2, attr)
   | "*", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PReal (v1 *. v2, p1, attr)
   | "*", PInt (v1, attr), PInt (v2, _) -> PInt (v1 * v2, attr)
   | "/", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PReal (v1 /. v2, p1, attr)
   | "/", PInt (v1, attr), PInt (v2, _) -> PInt (v1 / v2, attr)
   | "%", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PReal (mod_float v1 v2, p1, attr)
   | "%", PInt (v1, attr), PInt (v2, _) -> PInt (v1 mod v2, attr)
   | "==", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PBool (v1 = v2, attr)
   | "==", PInt (v1, attr), PInt (v2, _) -> PBool (v1 = v2, attr)
   | "<>", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PBool (v1 <> v2, attr)
   | "<>", PInt (v1, attr), PInt (v2, _) -> PBool (v1 <> v2, attr)
   | ">", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PBool (v1 > v2, attr)
   | ">", PInt (v1, attr), PInt (v2, _) -> PBool (v1 > v2, attr)
   | "<", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PBool (v1 < v2, attr)
   | "<", PInt (v1, attr), PInt (v2, _) -> PBool (v1 < v2, attr)
   | ">=", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PBool (v1 >= v2, attr)
   | ">=", PInt (v1, attr), PInt (v2, _) -> PBool (v1 >= v2, attr)
   | "<=", PReal (v1, p1, attr), PReal (v2, p2, _) when p1 = p2 -> PBool (v1 <= v2, attr)
   | "<=", PInt (v1, attr), PInt (v2, _) -> PBool (v1 <= v2, attr)
   | "&&", PBool (v1, attr), PBool (v2, _) -> PBool (v1 && v2, attr)
   | "||", PBool (v1, attr), PBool (v2, _) -> PBool (v1 || v2, attr)
   | _ -> POp (op, [ e1; e2 ], emptyAttr)


(** Used to perform series of arithmetic operations *)
let foldOp (op : string) (args : exp list) : exp =
   match args with
   | [] -> failwith ""
   | h :: t -> List.fold_left (evalOp op) h t


(** Adds all the builtin functions to the scope *)
let builtinFunctions (a : Args.args) env =
   let real_real f attr args : exp =
      match args with
      | [ PReal (v, p, _) ] -> PReal (f v, p, attr)
      | _ -> failwith "invalid arguments"
   in
   let clip attr args =
      match args with
      | [ PReal (v, p, _); PReal (mi, _, _); PReal (ma, _, _) ] -> PReal (max mi (min ma v), p, attr)
      | [ PInt (v, _); PInt (mi, _); PInt (ma, _) ] -> PInt (max mi (min ma v), attr)
      | _ -> failwith "clip: invalid arguments"
   in
   let int attr args =
      match args with
      | [ PReal (v, _, _) ] -> PInt (int_of_float v, attr)
      | [ PInt (v, _) ] -> PInt (v, attr)
      | [ PBool (v, _) ] -> PInt ((if v then 1 else 0), attr)
      | _ -> failwith "int: invalid arguments"
   in
   let real attr args =
      match args with
      | [ PReal (v, _, _) ] -> PReal (v, Float, attr)
      | [ PInt (v, _) ] -> PReal (float_of_int v, Float, attr)
      | [ PBool (v, _) ] -> PReal ((if v then 1.0 else 0.0), Float, attr)
      | _ -> failwith "real: invalid arguments"
   in
   let fix16 attr args =
      match args with
      | [ PReal (v, _, _) ] -> PReal (v, Fix16, attr)
      | [ PInt (v, _) ] -> PReal (float_of_int v, Fix16, attr)
      | [ PBool (v, _) ] -> PReal ((if v then 1.0 else 0.0), Fix16, attr)
      | _ -> failwith "fix16: invalid arguments"
   in
   let not attr args =
      match args with
      | [ PBool (v, _) ] -> PBool (not v, attr)
      | _ -> failwith "real: invalid arguments"
   in
   let eps attr args =
      match args with
      | [] -> PReal (1e-18, Float, attr)
      | _ -> failwith "eps: invalid arguments"
   in
   let pi attr args =
      match args with
      | [] -> PReal (3.1415926535897932384, Float, attr)
      | _ -> failwith "pi: invalid arguments"
   in
   (*let random attr args =
     match args with
     | [] -> PReal(Random.float 1.0, attr)
     | _ -> failwith "random: invalid arguments"
     in
     let irandom attr args =
     match args with
     | [] -> PInt(Random.int max_int, attr)
     | _ -> failwith "irandom: invalid arguments"
     in*)
   let log attr args =
      match args with
      | [ e ] ->
         print_endline (PrintProg.expressionStr e) ;
         PUnit attr
      | _ -> failwith "log: invalid arguments"
   in
   let get _attr args =
      match args with
      | [ PArray (elems, _); PInt (i, _) ] -> elems.(i)
      | _ -> failwith "get: invalid arguments"
   in
   let set attr args =
      match args with
      | [ PArray (elems, _); PInt (i, _); value ] ->
         elems.(i) <- value ;
         PUnit attr
      | _ -> failwith "get: invalid arguments"
   in
   let samplerate (a : Args.args) attr args =
      match args, a.fs with
      | [], Some n -> PReal (n, Float, attr)
      | _ -> raise Abort
   in
   let functions =
      [ "abs", Env.Builtin (real_real abs_float)
      ; "log10", Env.Builtin (real_real log10)
      ; "exp", Env.Builtin (real_real exp)
      ; "sin", Env.Builtin (real_real sin)
      ; "cos", Env.Builtin (real_real cos)
      ; "floor", Env.Builtin (real_real floor)
      ; "tanh", Env.Builtin (real_real tanh)
      ; "cosh", Env.Builtin (real_real cosh)
      ; "sinh", Env.Builtin (real_real sinh)
      ; "tan", Env.Builtin (real_real tan)
      ; "sqrt", Env.Builtin (real_real sqrt)
      ; "clip", Env.Builtin clip
      ; "int", Env.Builtin int
      ; "real", Env.Builtin real
      ; "fix16", Env.Builtin fix16
      ; "not", Env.Builtin not
      ; "eps", Env.Builtin eps
      ; "pi", Env.Builtin pi
      ; (*"random", Env.Builtin(random);
          "irandom", Env.Builtin(irandom);*)
        "log", Env.Builtin log
      ; "get", Env.Builtin get
      ; "set", Env.Builtin set
      ; "samplerate", Env.Builtin (samplerate a)
      ]
   in
   List.iter (fun (name, body) -> Env.addFunction env [ name ] body) functions


(** Defines which type of bind is performed *)
type bind_kind =
   | Update (* Simple update of an existing variable *)
   | DeclareVal (* Declaration of a local variable *)
   | DeclareMem

(* Declaration of a memory variable *)

(** Binds arguments of a function call to a local variable *)
let rec bindArg (env : Env.env) (lhs : typed_id) (rhs : exp) =
   match lhs, rhs with
   | (TypedId (id, _, _, _) | SimpleId (id, _, _)), rhs -> Env.updateVar env id rhs


let getIndex (id : exp) (index : exp) : exp option =
   match id, index with
   | PArray (elems, _), PInt (n, _) -> Some elems.(n)
   | _ -> None


(** Binds the an optional rhs to a lhs expression *)
let rec bind (kind : bind_kind) (env : Env.env) (lhs : lhs_exp) (rhs : exp option) =
   match lhs, rhs, kind with
   | LWild _, _, _ -> ()
   | LTyped (lhs, _, _), _, _
   |LGroup (lhs, _), _, _ ->
      bind kind env lhs rhs
   (* cases when the rhs is given *)
   | LId (id, _, _), Some rhs, Update -> Env.updateVar env id rhs
   | LId (id, _, _), Some rhs, DeclareVal -> Env.declareVal env id rhs
   | LId (id, _, _), Some rhs, DeclareMem -> Env.declareMem env id rhs
   | LTuple (lhs_elems, _), Some (PTuple (rhs_elems, _)), _ ->
      List.iter2 (fun l r -> bind kind env l (Some r)) lhs_elems rhs_elems
   (* cases in which the rhs is not given *)
   | LId (id, _, _), None, Update ->
      let rhs = getInitExp lhs in
      Env.updateVar env id rhs
   | LId (id, _, _), None, DeclareVal ->
      let rhs = getInitExp lhs in
      Env.declareVal env id rhs
   | LId (id, _, _), None, DeclareMem ->
      let rhs = getInitExp lhs in
      Env.declareMem env id rhs
   | LTuple (lhs_elems, _), None, _ -> List.iter (fun l -> bind kind env l None) lhs_elems
   | LIndex (id, _, _, _), None, DeclareVal ->
      let rhs = getInitExp lhs in
      Env.declareVal env id rhs
   | LIndex (id, _, _, _), None, DeclareMem ->
      let rhs = getInitExp lhs in
      Env.declareMem env id rhs
   | LIndex (id, _, index, _), Some rhs, Update ->
      let index = evalExp env index in
      Env.updateArrayVar env id index rhs
   | _ -> failwith ("Interpreter.bind: invalid input" ^ Prog.show_lhs_exp lhs)


(** Main function to evaluate an expression *)
and evalExp (env : Env.env) (exp : exp) : exp =
   match exp with
   | PEmpty -> PEmpty
   | PBool _ -> exp
   | PUnit _ -> exp
   | PInt _ -> exp
   | PReal _ -> exp
   | PString _ -> exp
   | PGroup (e, _) -> evalExp env e
   | PId (id, _) ->
      begin
         match Env.lookupVar env id with
         | value -> value
         | exception Not_found -> exp
      end
   | PIndex (e, index, attr) ->
      let value = evalExp env e in
      let index' = evalExp env index in
      begin
         match getIndex value index' with
         | Some v -> v
         | None -> PIndex (value, index', attr)
      end
   | PUnOp (op, exp, _) ->
      let exp' = evalExp env exp in
      evalUop op exp'
   | POp (op, elems, _) ->
      let elems' = List.map (evalExp env) elems in
      foldOp op elems'
   | PArray (elems, attr) ->
      let elems' = Array.map (evalExp env) elems in
      PArray (elems', attr)
   | PTuple (elems, attr) ->
      let elems' = List.map (evalExp env) elems in
      PTuple (elems', attr)
   | PIf (cond, then_, else_, attr) ->
      let cond' = evalExp env cond in
      begin
         match cond' with
         | PBool (true, _) -> evalExp env then_
         | PBool (false, _) -> evalExp env else_
         | _ -> PIf (cond', then_, else_, attr)
      end
   | PSeq (_, stmt, _) -> evalStmt env stmt
   | PCall (Named inst, name, args, attr) ->
      let args' = List.map (evalExp env) args in
      begin
         match Env.lookupFunction env name with
         | Some (t, fn) ->
            let env' = Env.enterInstance (t :: env) inst in
            begin
               match evalFunction env' fn attr args' with
               | Some exp -> exp
               | None -> exp
            end
         | None -> exp
      end
   | PCall (NoInst, name, args, attr) ->
      let args' = List.map (evalExp env) args in
      begin
         match Env.lookupFunction env name with
         | Some (t, fn) ->
            let inst = makeInstName name attr in
            let env' = Env.enterInstance (t :: env) inst in
            begin
               match evalFunction env' fn attr args' with
               | Some exp -> exp
               | None -> exp
            end
         | None -> raise Abort
      end
   | PCall (This, _, _, _) -> failwith "Self calls not yet implemented"


and evalFunction (env : Env.env) (fn : Env.fun_body) (attr : Prog.attr) (args : exp list) : exp option =
   match fn with
   | Env.Declared (StmtFun (_, inputs, stmt, _, _)) ->
      List.iter2 (bindArg env) inputs args ;
      Some (evalStmt env stmt)
   | Env.Builtin fn -> Some (fn attr args)
   | _ -> None


and evalStmt (env : Env.env) (stmt : stmt) =
   match stmt with
   | StmtVal (lhs, Some rhs, _) ->
      let rhs' = evalExp env rhs in
      bind Update env lhs (Some rhs') ;
      ret_unit
   | StmtVal (lhs, None, _) ->
      bind DeclareVal env lhs None ;
      ret_unit
   | StmtMem (lhs, Some rhs, _) ->
      let rhs' = evalExp env rhs in
      bind Update env lhs (Some rhs') ;
      ret_unit
   | StmtMem (lhs, None, _) ->
      bind DeclareMem env lhs None ;
      ret_unit
   | StmtBind (lhs, rhs, _) ->
      let rhs' = evalExp env rhs in
      bind Update env lhs (Some rhs') ;
      ret_unit
   | StmtReturn (e, _) -> evalExp env e
   | StmtBlock (_, stmts, _) ->
      let env' = Env.enterLocal env in
      evalStmts env' stmts
   | StmtFun (name, _, _, _, _) ->
      Env.addFunction env name (Env.Declared stmt) ;
      ret_unit
   | StmtEmpty -> ret_unit
   | StmtIf (cond, then_, None, _) ->
      let cond' = evalExp env cond in
      begin
         match cond' with
         | PBool (true, _) -> evalStmt env then_
         | PBool (false, _) -> ret_unit
         | _ -> failwith "could not evaluate if statement"
      end
   | StmtIf (cond, then_, Some else_, _) ->
      let cond' = evalExp env cond in
      begin
         match cond' with
         | PBool (true, _) -> evalStmt env then_
         | PBool (false, _) -> evalStmt env else_
         | _ -> failwith "could not evaluate if statement"
      end
   | StmtWhile (cond, body, _) ->
      let rec loop () =
         let cond' = evalExp env cond in
         match cond' with
         | PBool (true, _) ->
            let ret = evalStmt env body in
            begin
               match ret with
               | PUnit _ -> loop ()
               | _ -> ret
            end
         | PBool (false, _) -> ret_unit
         | _ -> failwith "condition cannot be evaluated"
      in
      loop ()
   | StmtType _ -> ret_unit
   | StmtAliasType _ -> ret_unit
   | StmtExternal (name, _, _, _, _) ->
      Env.addFunction env name Env.External ;
      ret_unit


(** Evaluates a list of statements *)
and evalStmts (env : Env.env) (stmts : stmt list) : exp =
   match stmts with
   | [] -> ret_unit
   | h :: t ->
      match evalStmt env h with
      | PUnit _ -> evalStmts env t
      | ret -> ret


let rec loadStmts (env : Env.env) (stmts : stmt list) : unit =
   match stmts with
   | [] -> ()
   | (StmtFun _ as h) :: t ->
      let _ = evalStmt env h in
      loadStmts env t
   | _ :: t -> loadStmts env t


let loadModule (env : Env.env) (results : parser_results) =
   let module_name = moduleName results.file in
   Env.addModule env [ module_name ] ;
   let env' = Env.enterModule env [ module_name ] in
   loadStmts env' results.presult


let evalModule (env : Env.env) (results : parser_results) =
   let module_name = moduleName results.file in
   Env.addModule env [ module_name ] ;
   let env' = Env.enterModule env [ module_name ] in
   evalStmts env' results.presult


(** Loads the functions without evaluating the top level statements *)
let load (a : Args.args) (results : parser_results list) : Env.env =
   let env = Env.top () in
   builtinFunctions a env ;
   let _ = results |> Inference.infer |> List.map (loadModule env) in
   env


(** Main function to evaluate the statements. *)
let eval (a : Args.args) (results : parser_results list) =
   let env = Env.top () in
   builtinFunctions a env ;
   results |> Inference.infer |> List.map (evalModule env)


let getEnv (a : Args.args) =
   let env = Env.top () in
   builtinFunctions a env ;
   env
