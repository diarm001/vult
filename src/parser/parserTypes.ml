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

type lexed_lines =
   {
      current_line      : Buffer.t;
      mutable all_lines : string list;
   }

(** Tokens *)
type token_enum =
   | EOF
   | INT
   | REAL
   | ID
   | FUN
   | MEM
   | VAL
   | RET
   | IF
   | THEN
   | ELSE
   | LBRAC
   | RBRAC
   | LPAREN
   | RPAREN
   | LSEQ
   | RSEQ
   | COLON
   | SEMI
   | COMMA
   | EQUAL
   | OP
   | AT
   | DOT
   | WHILE
   | TYPE
   | LARR
   | RARR
   | TRUE
   | FALSE
   | AND
   | WILD
   | EXTERNAL
   | TICK
   | ARROW
   | BANG

type 'kind token =
   {
      kind     : 'kind;
      value    : string;
      loc      : Loc.t;
   }

(** Type containing the stream of tokens *)
type 'kind stream =
   {
      lexbuf             : Lexing.lexbuf;
      mutable has_errors : bool;
      mutable errors     : Error.t list;
      mutable peeked     : 'kind token;
      mutable prev       : 'kind token;
      lines              : lexed_lines;
   }