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

(** Contains top level functions to perform common tasks *)

open TypesVult
open PassesUtil


(** Parses a string and runs it with the interpreter *)
let parseStringRun s =
   ParserVult.parseString s
   |> Passes.applyTransformations { PassesUtil.opt_full_transform with interpreter = true }
   |> DynInterpreter.interpret

(** Parses a string and runs it with the interpreter *)
let parseStringRunWithOptions options s =
   ParserVult.parseString s
   |> Passes.applyTransformations options
   |> DynInterpreter.interpret

(** Generates the .c and .h file contents for the given parsed files *)
let generateCCode (args:arguments) (parser_results:parser_results list) : string =
   let file = if args.output<>"" then args.output else "code" in
   let file_up = String.uppercase file in
   let stmts =
      parser_results
      |> List.map (Passes.applyTransformations { opt_full_transform with inline = true; codegen = true })
      |> List.map (
         fun a -> match a.presult with
            | `Ok(b) -> b
            | _ -> [] )
      |> List.flatten
   in

   let c_text,h_text = ProtoGenC.generateHeaderAndImpl args stmts in
   let c_final = Printf.sprintf "#include \"%s.h\"\n\n%s\n" file c_text in
   let h_final = Printf.sprintf
"#ifndef _%s_
#define _%s_

#include <math.h>
#include <stdint.h>
#include \"vultin.h\"

#ifdef __cplusplus
extern \"C\"
{
#endif

%s

#ifdef __cplusplus
}
#endif
#endif" file_up file_up h_text
   in
   let _ =
   if args.output<>"" then
      begin
         let oc = open_out (args.output^".c") in
         Printf.fprintf oc "%s\n" c_final;
         close_out oc;
         let oh = open_out (args.output^".h") in
         Printf.fprintf oh "%s\n" h_final;
         close_out oh
      end
   else
      begin
         print_endline h_final;
         print_endline c_final;
      end
   in h_final^c_final

(** Generates the .c and .h file contents for the given parsed files *)
let generateJSCode (args:arguments) (parser_results:parser_results list) : string =
   let stmts =
      parser_results
      |> List.map (Passes.applyTransformations { opt_full_transform with inline = false; codegen = true })
      |> List.map (
         fun a -> match a.presult with
            | `Ok(b) -> b
            | _ -> [] )
      |> List.flatten
   in

   let js_text = ProtoGenJS.generateModule args stmts in
   let js_final =
      Printf.sprintf
"function Process(){
 this.clip = function(x,low,high) { return x<low?low:(x>high?high:x); };
 this.not  = function(x) { x==0?1:0; };
 %s
 this.context = {};
 this._live_struct_process_init(this.context);
 this.live__default(this.context);
 this.context.param1_in = 0.0;
 this.context.param2_in = 0.0;
 this.context.param3_in = 0.5;
 this.context.param4_in = 0.054;
 this.context.param5_in = 0.157;
 this.context.param6_in = 1;
 this.context.param7_in = 0.43;
 this.context.param8_in = 0;
 this.context.param9_in = 0;
 this.context.param10_in = 0;
 this.context.param11_in = 1;
 this.context.param12_in = 0;
 this.context.param13_in = 0.1;
 this.context.param14_in = 0;
 this.context.param15_in = 0;
 this.context.param16_in = 0;
 this.go = function(i){
   this.context.param1 =this.context.param1+ (this.context.param1_in-this.context.param1)*0.01;
   this.context.param2 =this.context.param2+ (this.context.param2_in-this.context.param2)*0.01;
   this.context.param3 =this.context.param3+ (this.context.param3_in-this.context.param3)*0.01;
   this.context.param4 =this.context.param4+ (this.context.param4_in-this.context.param4)*0.01;
   this.context.param5 =this.context.param5+ (this.context.param5_in-this.context.param5)*0.01;
   this.context.param6 =this.context.param6+ (this.context.param6_in-this.context.param6)*0.01;
   this.context.param7 =this.context.param7+ (this.context.param7_in-this.context.param7)*0.01;
   this.context.param8 =this.context.param8+ (this.context.param8_in-this.context.param8)*0.01;
   this.context.param9 =this.context.param9+ (this.context.param9_in-this.context.param9)*0.01;
   this.context.param10=this.context.param10+(this.context.param10_in-this.context.param10)*0.01;
   this.context.param11=this.context.param11+(this.context.param11_in-this.context.param11)*0.01;
   this.context.param12=this.context.param12+(this.context.param12_in-this.context.param12)*0.01;
   this.context.param13=this.context.param13+(this.context.param13_in-this.context.param13)*0.01;
   this.context.param14=this.context.param14+(this.context.param14_in-this.context.param14)*0.01;
   this.context.param15=this.context.param15+(this.context.param15_in-this.context.param15)*0.01;
   this.context.param16=this.context.param16+(this.context.param16_in-this.context.param16)*0.01;
   return this.live__process(this.context,i);
 }
}
new Process()"
   js_text
   in
   if args.output<>"" then
      begin
         let oc = open_out (args.output^".js") in
         Printf.fprintf oc "%s\n" js_final;
         close_out oc;
         js_final
      end
   else
      begin
         print_endline js_final;
         js_final
      end

let generateCode (args:arguments) (parser_results:parser_results list) : string =
   if args.ccode then
      generateCCode args parser_results
   else
   if args.jscode then
      generateJSCode args parser_results
   else ""


let parseStringGenerateCode s =
   ParserVult.parseString s
   |> fun a -> generateCode default_arguments [a]

