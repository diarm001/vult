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

open Args
open Js_of_ocaml

let generateJSCode s =
   let args =
      { default_arguments with
        code = JSCode
      ; real = "js"
      ; template = "browser"
      ; files = [ Code ("live.vult", Js.to_string s) ]
      }
   in
   match Driver.main args with
   | [ GeneratedCode [ (code, _) ] ] -> Js.string (Pla.print code)
   | [ Errors errors ] ->
      let error_strings =
         List.map
            (fun error ->
                let msg, _, _, _ = Error.reportErrorStringNoLoc error in
                msg)
            errors
         |> String.concat "\n"
      in
      Js.string ("Errors in the program:\n" ^ error_strings)
   | _ -> Js.string "unknown error"


let makeAceError (e : Error.t) =
   let msg, _, line, col = Error.reportErrorStringNoLoc e in
   Js.Unsafe.obj
      [| "text", Js.Unsafe.inject (Js.string msg)
       ; "row", Js.Unsafe.inject (Js.string (string_of_int (line - 1)))
       ; "column", Js.Unsafe.inject (Js.string (string_of_int (col - 1)))
       ; "type", Js.Unsafe.inject (Js.string "error")
       ; "raw", Js.Unsafe.inject (Js.string msg)
      |]


let checkCode s =
   let args = { default_arguments with check = true; files = [ Code ("live.vult", Js.to_string s) ] } in
   match Driver.main args with
   | [ Errors errors ] ->
      let error_objects = List.map makeAceError errors in
      error_objects |> Array.of_list |> Js.array
   | _ -> Js.array [||]


let _ =
   Js.export
      "vult"
      (object%js
         method main = Vultlib.main

         method version = Vultlib.version

         method generateJs = Vultlib.generateJs

         method generateC = Vultlib.generateC

         method generateLua = Vultlib.generateLua

         method checkCode = checkCode

         method generateJSCode = generateJSCode
      end)
