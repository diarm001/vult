open Prog

module TypeMap = Map.Make (struct
  type t = Typ.t

  let compare = Typ.compare
end)

type state =
  { max_array_size : int
  ; max_tuple_size : int
  ; max_type_levels : int
  ; max_int : int
  ; max_real : float
  ; nest_prob : float
  ; get_array_type : bool
  ; get_tuple_type : bool
  ; get_if_exp : bool
  ; vars : Id.t list TypeMap.t
  ; return_type : Typ.t option
  }

type condition = state -> bool

type probability = state -> float

type 'a creator = state -> 'a

let default_state =
  { max_array_size = 100
  ; max_tuple_size = 3
  ; max_int = 100
  ; max_real = 1.0
  ; get_array_type = true
  ; get_tuple_type = true
  ; max_type_levels = 2
  ; nest_prob = 1.0
  ; vars = TypeMap.empty
  ; get_if_exp = true
  ; return_type = None
  }


let rec fold_init f s n =
  if n > 0 then
    let s', e = f s in
    let s', e' = fold_init f s' (n - 1) in
    s', e :: e'
  else
    s, []


let rec get_elem state min max (n : float) (elems : (condition * probability * 'a creator) list) =
  match elems with
  | h :: ((_, p, _) :: _ as t) ->
      if n >= min && n <= max then
        h
      else
        get_elem state max (max +. p state) n t
  | h :: _ ->
      if n >= min && n <= max then
        h
      else
        failwith "get_elem: invalid input"
  | [] -> failwith "get_elem: invalid input"


let rec filter_count state acc l =
  match l with
  | [] ->
      let n, e = acc in
      n, List.rev e
  | ((c, p, _) as h) :: t ->
      let n, e = acc in
      if c state then
        let prob = p state in
        if prob > 0.0 then
          filter_count state (n +. prob, h :: e) t
        else
          filter_count state acc t
      else
        filter_count state acc t


let pick_one state (elems : (condition * probability * 'a creator) list) : 'a =
  let total, elems' = filter_count state (0.0, []) elems in
  let n = Random.float total in
  let _, first_p, _ = List.hd elems' in
  let _, _, f = get_elem state 0.0 (first_p state) n elems' in
  f state


let makeArray state t =
  let n = Random.int (state.max_array_size - 1) + 1 in
  let size = ref (Typ.TInt (n, None)) in
  ref (Typ.TComposed ([ "array" ], [ t; size ], None))


let makeTuple elems = ref (Typ.TComposed ([ "tuple" ], elems, None))

let normal_p _ = 1.0

let high_p _ = 2.0

let low_p _ = 0.3

let nest_p state = state.nest_prob

let always _ = true

let with_array state = state.get_array_type

let with_if_exp state = state.get_if_exp

let with_tuple state = state.get_tuple_type && state.max_type_levels > 0

let no_array state = { state with get_array_type = false }

let no_tuple state = { state with get_tuple_type = false }

let no_if_exp state = { state with get_if_exp = false }

let decr_level state = { state with max_type_levels = state.max_type_levels - 1 }

let decr_nest state = { state with nest_prob = state.nest_prob *. 0.5 }

let rec newType state =
  pick_one
    state
    [ (always, normal_p, fun _ -> Typ.Const.int_type)
    ; (always, normal_p, fun _ -> Typ.Const.real_type)
    ; (always, normal_p, fun _ -> Typ.Const.bool_type)
    ; (* Array *)
      ( with_array
      , low_p
      , fun state ->
          let state' = no_tuple (no_array state) in
          let t = newType state' in
          makeArray state' t )
    ; (* Tuple *)
      ( with_tuple
      , low_p
      , fun state ->
          let nelems = 2 + Random.int (state.max_tuple_size - 2) in
          let state' = decr_level (no_array state) in
          let t = newTypeList nelems state' in
          makeTuple t )
    ]


and newTypeList n state =
  if n = 0 then
    []
  else
    newType state :: newTypeList (n - 1) state


let isInt typ _ = Typ.compare Typ.Const.int_type typ = 0

let isReal typ _ = Typ.compare Typ.Const.real_type typ = 0

let isBool typ _ = Typ.compare Typ.Const.bool_type typ = 0

let isNum typ state = isReal typ state || isInt typ state

let isArray typ _ =
  match !typ with
  | Typ.TComposed ([ "array" ], _, _) -> true
  | _ -> false


let isArrayOfType subtype typ =
  match !typ with
  | Typ.TComposed ([ "array" ], [ t; { contents = Typ.TInt (_, _) } ], _) -> Typ.compare subtype t = 0
  | _ -> false


let isTuple typ _ =
  match !typ with
  | Typ.TComposed ([ "tuple" ], _, _) -> true
  | _ -> false


let tupleTypes typ =
  match !typ with
  | Typ.TComposed ([ "tuple" ], elems, _) -> elems
  | _ -> failwith "tupleTypes: invalid input"


let pickVar state typ =
  let elems = TypeMap.find typ state.vars in
  let size = List.length elems in
  let n = Random.int size in
  List.nth elems n


let hasType typ state = TypeMap.mem typ state.vars

let hasArrayType typ state = TypeMap.exists (fun key _ -> isArrayOfType typ key) state.vars

let pickArrayVar state typ =
  TypeMap.bindings state.vars
  |> List.filter (fun (key, _) -> isArrayOfType typ key)
  |> List.map (fun (key, names) -> List.map (fun n -> key, n) names)
  |> List.flatten
  |> List.map (fun x -> always, normal_p, fun _ -> x)
  |> pick_one state


let hasVar state name = TypeMap.exists (fun _ names -> List.exists (fun n -> n = name) names) state.vars

let addVar state var typ =
  match TypeMap.find typ state.vars with
  | elems ->
      let vars = TypeMap.add typ (var :: elems) state.vars in
      { state with vars }
  | exception Not_found ->
      let vars = TypeMap.add typ [ var ] state.vars in
      { state with vars }


let newNumBiOp state =
  pick_one
    state
    [ (always, normal_p, fun _ -> "+")
    ; (always, normal_p, fun _ -> "-")
    ; (always, normal_p, fun _ -> "*")
    ; (always, normal_p, fun _ -> "/")
    ; (always, normal_p, fun _ -> "%")
    ]


let newBoolBiOp state = pick_one state [ (always, normal_p, fun _ -> "&&"); (always, normal_p, fun _ -> "||") ]

let newLogicBiOp state =
  pick_one
    state
    [ (always, normal_p, fun _ -> ">")
    ; (always, normal_p, fun _ -> "<")
    ; (always, normal_p, fun _ -> ">=")
    ; (always, normal_p, fun _ -> "<=")
    ; (always, normal_p, fun _ -> "==")
    ; (always, normal_p, fun _ -> "<>")
    ]


let newBuiltinFun state =
  pick_one
    state
    [ (always, normal_p, fun _ -> "abs")
    ; (always, normal_p, fun _ -> "exp")
    ; (always, normal_p, fun _ -> "sin")
    ; (always, normal_p, fun _ -> "cos")
    ; (always, normal_p, fun _ -> "floor")
    ; (always, normal_p, fun _ -> "tanh")
    ]


let newBuiltinFunNoArgs state = pick_one state [ (always, normal_p, fun _ -> "eps"); (always, normal_p, fun _ -> "pi") ]

let rec newExp state typ =
  pick_one
    state
    [ (isInt typ, normal_p, fun state -> PInt (Random.int state.max_int + 1, emptyAttr))
    ; (isReal typ, normal_p, fun state -> PReal (Random.float state.max_real +. 1.0, Float, emptyAttr))
    ; (isBool typ, low_p, fun _ -> PBool (Random.bool (), emptyAttr))
    ; (hasType typ, high_p, fun state -> PId (pickVar state typ, emptyAttr))
    ; (* literal array *)
      ( isArray typ
      , low_p
      , fun state ->
          let array_type, size = Typ.arrayTypeAndSize typ in
          let elems = newExpArray size state array_type in
          PArray (elems, emptyAttr) )
    ; (* call real builtin *)
      ( isReal typ
      , nest_p
      , fun state ->
          let state' = decr_nest state in
          let elem = newExp state' typ in
          let fn = newBuiltinFun state' in
          PCall (NoInst, [ fn ], [ elem ], emptyAttr) )
    ; (* call real builtin no args *)
      ( isReal typ
      , nest_p
      , fun state ->
          let state' = decr_nest state in
          let fn = newBuiltinFunNoArgs state' in
          PCall (NoInst, [ fn ], [], emptyAttr) )
    ; (* call to get array*)
      ( hasArrayType typ
      , nest_p
      , fun state ->
          let array_type, var = pickArrayVar state typ in
          let _, size = Typ.arrayTypeAndSize array_type in
          let index = Random.int size in
          PIndex (PId (var, emptyAttr), PInt (index, emptyAttr), emptyAttr) )
    ; (* tuples *)
      ( isTuple typ
      , low_p
      , fun state ->
          let types = tupleTypes typ in
          let elems = List.map (newExp state) types in
          PGroup (PTuple (elems, emptyAttr), emptyAttr) )
    ; (* operators *)
      ( isNum typ
      , nest_p
      , fun state ->
          let state' = decr_nest state in
          let e1 = newExp state' typ in
          let e2 = newExp state' typ in
          let op = newNumBiOp state' in
          POp (op, [ e1; e2 ], emptyAttr) )
    ; ( isBool typ
      , nest_p
      , fun state ->
          let state' = decr_nest state in
          let e1 = newExp state' typ in
          let e2 = newExp state' typ in
          let op = newBoolBiOp state' in
          POp (op, [ e1; e2 ], emptyAttr) )
    ; ( isBool typ
      , nest_p
      , fun state ->
          let state' = decr_nest state in
          let t = newType state' in
          if isNum t state then
            let e1 = newExp state' t in
            let e2 = newExp state' t in
            let op = newLogicBiOp state' in
            POp (op, [ e1; e2 ], emptyAttr)
          else
            newExp state typ )
    ; (* if-expression *)
      ( with_if_exp
      , nest_p
      , fun state ->
          let cond = newExp state Typ.Const.bool_type in
          let state' = decr_nest state in
          let e1 = newExp state' typ in
          let e2 = newExp state' typ in
          PIf (cond, e1, e2, emptyAttr) )
    ]


and newExpList n state typ =
  if n = 0 then
    []
  else
    newExp state typ :: newExpList (n - 1) state typ


and newExpArray n state typ = newExpList n state typ |> Array.of_list

let rec getName state =
  let random_char _ =
    let n = Random.int (Char.code 'z' - Char.code 'a') + Char.code 'a' in
    Char.chr n
  in
  let number = String.init 10 random_char in
  let name = [ "tmp_" ^ number ] in
  if hasVar state name then
    getName state
  else
    name


let rec newLExpDecl state typ =
  pick_one
    state
    [ (* new variable *)
      ( always
      , normal_p
      , fun state ->
          let name = getName state in
          let state' = addVar state name typ in
          LId (name, None, emptyAttr), state' )
    ; (* wild *)
      (always, low_p, fun state -> LTyped (LWild emptyAttr, typ, emptyAttr), state)
    ; (* tuple *)
      ( isTuple typ
      , normal_p
      , fun state ->
          let types = tupleTypes typ in
          let state', lhs_elems =
            List.fold_left
              (fun (s, acc) t ->
                let t', s' = newLExpDecl s t in
                s', t' :: acc)
              (state, [])
              types
          in
          LTuple (List.rev lhs_elems, emptyAttr), state' )
    ]


let rec newLExpBind state typ =
  pick_one
    state
    [ (* pick variable *)
      ( hasType typ
      , high_p
      , fun state ->
          let name = pickVar state typ in
          LId (name, None, emptyAttr), state )
    ; (* wild *)
      (always, low_p, fun state -> LWild emptyAttr, state)
    ; (* tuple *)
      ( isTuple typ
      , normal_p
      , fun state ->
          let types = tupleTypes typ in
          let state', lhs_elems =
            List.fold_left
              (fun (s, acc) t ->
                let t', s' = newLExpBind s t in
                s', t' :: acc)
              (state, [])
              types
          in
          LTuple (List.rev lhs_elems, emptyAttr), state' )
    ]


let returnType state =
  match state.return_type with
  | Some t -> state, t
  | _ ->
      let t = newType state in
      let state' = { state with return_type = Some t } in
      state', t


let restoreVars new_vars old = { new_vars with vars = old.vars }

let rec newStmt state =
  pick_one
    state
    [ (* val *)
      ( always
      , normal_p
      , fun state ->
          let t = newType state in
          let lhs, state' = newLExpDecl state t in
          (* here use the old state to not pick the new variable *)
          let rhs = newExp state t in
          state', StmtVal (lhs, Some rhs, emptyAttr) )
    ; ( always
      , low_p
      , fun state ->
          let t = newType state in
          let lhs, state' = newLExpDecl state t in
          let lhs' = LTyped (lhs, t, emptyAttr) in
          state', StmtVal (lhs', None, emptyAttr) )
    ; (* mem *)
      ( always
      , normal_p
      , fun state ->
          let t = newType state in
          let lhs, state' = newLExpDecl state t in
          (* here use the new state to make possible picking the new variable *)
          let rhs = newExp state' t in
          let lhs' = LTyped (lhs, t, emptyAttr) in
          state', StmtMem (lhs', Some rhs, emptyAttr) )
    ; ( always
      , low_p
      , fun state ->
          let t = newType state in
          let lhs, state' = newLExpDecl state t in
          (* here use the new state to make possible picking the new variable *)
          let lhs' = LTyped (lhs, t, emptyAttr) in
          state', StmtMem (lhs', None, emptyAttr) )
    ; (* bind *)
      ( always
      , normal_p
      , fun state ->
          let t = newType state in
          if hasType t state then
            let lhs, state' = newLExpBind state t in
            (* here use the new state to make possible picking the new variable *)
            let rhs = newExp state' t in
            state', StmtBind (lhs, rhs, emptyAttr)
          else
            newStmt state )
    ; (* return *)
      ( always
      , low_p
      , fun state ->
          let state', t = returnType state in
          let e = newExp state t in
          state', StmtReturn (e, emptyAttr) )
    ; (* if statements *)
      ( always
      , low_p
      , fun state ->
          let cond = newExp state Typ.Const.bool_type in
          let state', e1 = newStmtList 3 state in
          let state', e2 = newStmtList 3 (restoreVars state' state) in
          let state' = restoreVars state' state in
          state', StmtIf (cond, StmtBlock (None, e1, emptyAttr), Some (StmtBlock (None, e2, emptyAttr)), emptyAttr) )
    ; ( always
      , low_p
      , fun state ->
          let cond = newExp state Typ.Const.bool_type in
          let state', e1 = newStmtList 3 state in
          let state' = restoreVars state' state in
          state', StmtIf (cond, StmtBlock (None, e1, emptyAttr), None, emptyAttr) )
    ; ( always
      , low_p
      , fun state ->
          let cond = newExp state Typ.Const.bool_type in
          let state', e1 = newStmtList 3 state in
          let state' = restoreVars state' state in
          state', StmtWhile (cond, StmtBlock (None, e1, emptyAttr), emptyAttr) )
    ]


and newStmtList n state : state * stmt list = fold_init newStmt state n

let newFunction () =
  let name = [ "foo_" ^ string_of_int (Random.int 10000) ] in
  let _, stmts = newStmtList 100 default_state in
  StmtFun (name, [], StmtBlock (None, stmts, emptyAttr), None, emptyAttr)


let test seed =
  Random.init seed ;
  let stmts = [ newFunction () ] in
  let code = PrintProg.stmtListStr stmts in
  code


let run seed = test seed
