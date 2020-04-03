type print_buffer =
   { buffer : Buffer.t
   ; mutable indent : int
   ; mutable space : string
   ; mutable insert : bool
   }
(** String buffer with a few useful functions *)

(** Creates a print buffer *)
let makePrintBuffer () = { buffer = Buffer.create 100; indent = 0; space = ""; insert = false }

(** Inserts a new line to the print buffer *)
let newline buffer =
   Buffer.add_string buffer.buffer "\n" ;
   buffer.insert <- true


(** Inserts a new line and indents all strings appended *)
let indent buffer =
   buffer.indent <- buffer.indent + 1 ;
   buffer.space <- String.make (buffer.indent * 3) ' ' ;
   newline buffer


(** Removes one indentation step *)
let outdent buffer =
   buffer.indent <- buffer.indent - 1 ;
   if buffer.indent < 0 then
      failwith "Cannot outdent more" ;
   buffer.space <- String.make (buffer.indent * 3) ' '


(** Inserts a string to the print buffer *)
let append buffer s =
   if buffer.insert then (
      Buffer.add_string buffer.buffer buffer.space ;
      buffer.insert <- false ) ;
   Buffer.add_string buffer.buffer s


(** Returns the contents of the print buffer *)
let contents buffer = Buffer.contents buffer.buffer

(** Function for printing list of elements *)
let rec printList buffer f sep l =
   match l with
   | [] -> ()
   | [ h ] -> f buffer h
   | h :: t ->
      f buffer h ;
      append buffer sep ;
      printList buffer f sep t


let printArray buffer f sep l =
   let n = Array.length l in
   let rec loop i =
      if i = n - 1 then
         let h = l.(i) in
         f buffer h
      else
         let h = l.(i) in
         let () = f buffer h in
         let () = append buffer sep in
         loop (i + 1)
   in
   if n > 0 then loop 0


(** Function for printing list of elements *)
let rec printListSepLast buffer f sep l =
   match l with
   | [] -> ()
   | [ h ] ->
      f buffer h ;
      sep buffer
   | h :: t ->
      f buffer h ;
      sep buffer ;
      printListSepLast buffer f sep t


(** Function for printing list of elements *)
let rec printListSep buffer f sep l =
   match l with
   | [] -> ()
   | [ h ] -> f buffer h
   | h :: t ->
      f buffer h ;
      sep buffer ;
      printListSep buffer f sep t
