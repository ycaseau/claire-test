//+-------------------------------------------------------------+
//| CLAIRE                                                      |
//| file.cl                                                     |
//| Copyright (C) 1994 - 2003 Yves Caseau. All Rights Reserved  |
//| cf. copyright info in file object.cl: about()               |
//+-------------------------------------------------------------+


// ---------------------------------------------------------------------
// Contents:
//   Part 1: Utilities
//   Part 2: Loading
//   Part 3: Reading
//   Part 4: Top-level
//   Part 5: The show & kill compiled_methods
// ---------------------------------------------------------------------

// **********************************************************************
// *   Part 1: Utilities                                                *
// **********************************************************************


// useful gadgets
//
[self_eval(self:delimiter) : any
 -> next(reader),                       // v3.1.04 better safe than sorry
    error("[117] loose delimiter ~S in program [line ~A ?]", self, reader.nb_line)]

(put(mClaire/evaluate, delimiter, (self_eval @ delimiter).functional))

// a small useful function
// PORTABILITY WARNING: the following assumes newline is ^J (ASCII 10 dec)
// PORTABILITY WARNING: what about ^M (ASCII 13 dec)
//
// a small usefull function
[useless_c(r:integer) : boolean
 -> if (r = 10 | r = 13) write(nb_line, reader, reader.nb_line + 1),
    (r = reader.space | r = 10 | r = 13 | r = 32 | r = reader.tab) ]

// take care of PC format (10 + 13)
skipc(self:meta_reader) : any
 -> (while useless_c(firstc(self))
           let b := (firstc(self) = 10) in
             (next(self), if (b & firstc(self) = 13) next(self)),
     firstc(self))

// look for a meaningful termination char such as ) or ]
skipc!(r:meta_reader) : any
 -> (let c := skipc(r) in
       (if (c = 59)
           (while (r.firstc != r.eof & r.firstc != 10) next(r),
            if (r.firstc = r.eof) EOF
            else (write(nb_line, r, r.nb_line + 1), skipc!(r)))
        else if (c = 47)
           let x := Kernel/read_ident(r.fromp) in
              (if (x % string) skipc!(r) else 47)
        else c))

cnext(self:meta_reader) : meta_reader -> (next(self), self)
findeol(self:meta_reader) : boolean
 -> ((while useless_c(firstc(self))
        (if (firstc(self) = 10) break(true), next(self))) |
     firstc(self) = self.eof)

// safety checking
//
checkno(r:meta_reader,n:integer,y:any) : any
 -> (if (r.firstc != n) r
     else Serror("[118] read wrong char ~S after ~S", list(char!(n), y)))

// reads a keyword inside a control structure
//
verify(t:any,x:any,y:any) : any
 -> (if (x % t) x
     else Serror("[119] read ~S instead of a ~S in a ~S", list(x, t, y)))

// prints a syntax error
//
Serror(s:string,la:list) : {}
  -> (printf("---- Syntax Error[line: ~A]:\n", reader.nb_line),
      flush(reader.fromp),
      general_error(cause = s, arg = la))

; -> (printf("Syntax error: ~I\n", format(s, la)),
;     flush(reader.fromp),
;     error("Error occurred in line ~A", reader.nb_line))

// the reader-------------------------------------------------------------
//
reader :: meta_reader(space = 202,
                      eof = externC("((int) EOF)",integer),          // should be -1
                      tab = 9, index = 1,
                      external = "toplevel",
                      bracket = mClaire/new!(delimiter, symbol!("]")),
                      paren = mClaire/new!(delimiter, symbol!(")")),
                      comma = mClaire/new!(delimiter, symbol!(",")),
                      curly = mClaire/new!(delimiter, symbol!("}")))

// variable handling -------------------------------------------------
// reads a variable
//
extract_variable(self:any) : Variable
 -> (if (case self (Variable get(self.mClaire/pname) != self))
        (put(range, self as Variable, extract_type(self.range)),
         self as Variable)
     else let v := Variable(mClaire/pname = extract_symbol(self)) in
            (reader.last_form := v, v))

// create a variable and add it to the lexical environment
bind!(self:meta_reader,%v:Variable) : list
 -> (put(index, %v, self.index),
     let value := get(%v.mClaire/pname) in
       (put(index, self, self.index + 1),
        if (self.index > self.maxstack) put(maxstack, self, self.index),
        put(%v.mClaire/pname, %v),
        list(%v, value)))

// remove a variable from the lexical environment
//
unbind!(self:meta_reader,%first:list) : any
 -> (let var := %first[1] in
       (put(index, self, self.index - 1),
        put(var.mClaire/pname, %first[2])))

// declaration of the CLAIRE standard ports ----------------------------
// the internal standard ports are transmitted via two strings in the
// symbol table.
//
stdout :: global_variable(range = port,
                          value = get(symbol!("STDOUT", claire)))
(write(ctrace, system, stdout))

stdin :: global_variable(range = port,
                         value = get(symbol!("STDIN", claire)))

*fs*:string :: Id(*fs*)

/(s:string,s2:string) : string -> ((s /+ *fs*) /+ s2)

// basic methods defined in creader.c -----------------------------------
// TODO move!
// flush(self:port) : any -> function!(flush_port)

// this function is called by the main and restores the reader in a good shape. Also
// closes the input port to free the associated file ! <yc>
[Core/restore_state(self:meta_reader) : void
 ->  if (self.fromp != stdin) fclose(self.fromp),
     put(fromp, self, stdin),
     put(index, self, 1),
     flush(stdin,32),                            // v3.3.10  
     Core/restore_state() ]

// *********************************************************************
// *   Part 2: Loading                                                 *
// *********************************************************************


// sload is the interactive version.
//
load_file(self:string,b:boolean) : any
 -> (write(index, reader, 0),
     write(maxstack, reader, 0),
     reader.nb_line := 1,
     reader.external := self,
     trace(2, "---- [load CLAIRE file: ~A]\n", self),
//     try
     let s2 := (self /+ ".cl"),
         p1:port := (try fopen(s2, "r")
                     catch any try fopen(self, "r")
                     catch any error("[120] the file ~A cannot be opened", self)),
         start := mClaire/base!(),  top := mClaire/index!(),
         p2 := reader.fromp,
         b2 := reader.toplevel,     // v3.1.16 !! remove c2 = ....
         *item* := unknown in
       (mClaire/set_base(top),
        reader.fromp := p1,
       // reader.firstc := 32,
        reader.toplevel := false,
        *item* := readblock(p1),
        while not(*item* = eof)
          (if b printf("~A:~S\n",reader.nb_line,*item*),
           mClaire/set_index(top + (reader.maxstack + 1)),
           case *item* 
             (string (if NeedComment      // v3.1.16 -> improve comment
                       (if known?(Language/LastComment)
                           Language/LastComment :/+ ("\n-- " /+ *item*)  
                        else Language/LastComment :=
                                     ("[" /+ reader.external /+ "(" /+ string!(reader.nb_line)
                                       /+ ")]\n-- " /+ *item*))),
              any (*item* := eval(*item*), 
                   Language/LastComment := unknown)),
           if b printf("=> ~S \n\n", *item*),
           *item* := readblock(p1)),
        mClaire/set_base(start),
        mClaire/set_index(top),
        reader.toplevel := b2,
        reader.fromp := p2,
        reader.external := "toplevel",
        fclose(p1)),
//     catch general_error
//       (printf("---- file ~S, line ~S\n",self,reader.nb_line),
//        close(system.exception!)),
     true)

// the simple load
//
load(self:string) : any -> load_file(self, false)
sload(self:string) : any -> load_file(self, true)

// loading a module into the system.
// The correct package is open and each file is loaded.
[load_file(self:module,b:boolean) : void
 ->  if (self.mClaire/status = 2)
        (funcall(self.mClaire/evaluate, any, any, any),
         self.mClaire/status := 3)
     else if (self.mClaire/status = 0 & known?(source,self))
        (trace(3, "---- Loading the module ~S.\n", self),
         begin(self),
         let s := (self.source /+ *fs*) in
           for x in self.made_of load_file((s /+ x) /+ ".cl", b),
         self.mClaire/status := 1),
     end(self) ]

// the simple load
//
load(self:module) : any
 -> (for x in add_modules(list(self)) load_file(x, false))
sload(self:module) : any
 -> (for x in add_modules(list(self)) load_file(x, true))

// This is a very important method which adds the right order the
// modules that must be loaded to load oself. the list l represents the
// list of modules that we know will be in the result. result represent
// the current list of ordered modules
//
add_modules(self:module,l:set,result:list) : list
 -> (if (self % result) result
     else if (self % l) result add self
     else (l := l add self,
           for x in self.uses
             case x (module result := add_modules(x, l, result)),
           if not(self % result) result := result add self,
           for x in self.parts result := add_modules(x, l, result),
           result))

// this methods takes a list of modules that must be loaded and returns
// a list of modules that are necessary for the definition
//
add_modules(self:list) : list
 -> (let l := list<module>() in
       (for x in self l := add_modules(x, set!(l), l), l))

// load a file of expressions (quite useful)
eload(self:string) : any
 -> (reader.index := 0,
     reader.maxstack := 0,
     reader.nb_line := 1,
     reader.external := self,
     trace(2, "---- [eload CLAIRE file: ~A]\n", self),
     let s2 := (self /+ ".cl"),
         p0:port := reader.fromp, // c0 := reader.firstc,
         p1:port := (try fopen(s2, "r")
                     catch any try fopen(self, "r")
                     catch any error("[120] the file ~A cannot be opened", self)),
         start := mClaire/base!(),
         top := mClaire/index!(),
         b2 := reader.toplevel,
         *item* := unknown in
       (mClaire/set_base(top),
        reader.toplevel := false,
        reader.fromp := p1,
        *item* := read(p1),
        while not(*item* = eof)
          (mClaire/set_index(top + (reader.maxstack + 1)),
           *item* := eval(*item*),
           *item* := read(p1)),
        mClaire/set_base(start),
        mClaire/set_index(top),
        reader.fromp := p0,
    //    reader.firstc := c0,                                 v3.2.36 !
        reader.toplevel := b2,
        reader.external := "toplevel",
        fclose(p1)),
   true)


// *********************************************************************
// *   Part 3: Read & Top-level                                        *
// *********************************************************************

// The standard read function.
// This method reads from a CLAIRE port (self).
// We first check if self is the current reading port.
// the last character read (and not used) is in last(reader)
[readblock(p:port) : any
 ->  if (reader.fromp = p) nextunit(reader)
     else let // v := reader.firstc,
              p2 := reader.fromp in
            (put(fromp, reader, p),
             let val := nextunit(reader) in
               (put(fromp, reader, p2),
                if (val = paren(reader) | val = curly(reader) | val = comma(reader) | val = bracket(reader))
                   Serror("[117] Loose ~S in file", list(val)),
                val)) ]

// read reads a closed expression
[read(p:port) : any
 -> let p2 := reader.fromp in
    //    v := reader.firstc in
       (if (p != p2) (put(fromp, reader, p)), // , put(firstc, reader, 32)),
        let val := (if (skipc(reader) = reader.eof) eof
         else nexte(reader)) in
          (if (p != p2) put(fromp, reader, p2),
           if  (val = paren(reader) | val = curly(reader) | val = comma(reader) | val = bracket(reader))
               Serror("[117] Loose ~S in file", list(val)),
           val)) ]

// read into a string
[read(self:string) : any
 ->  let b := reader.toplevel,
         p := reader.fromp,
         x := unknown in
      (reader.toplevel := true,
       reader.fromp := port!(self),
       try (x := nextunit(reader),
            reader.fromp := p)
       catch any (reader.fromp := p,
                   close@exception(system.exception!)),
       reader.toplevel := b,
       x) ]

q :: keyword()
call_debug :: property()

// used by the top level
EVAL[i:(0 .. 99)] : any := unknown

// calls the debugger
debug_if_possible() : any
 -> (if (system.Kernel/debug! >= 0)
        funcall((call_debug.restrictions[1] as method).functional, any,
              system, any)
     else print_exception())

// a method for calling the printer without issuing a message (that would
// modify the stack and make debugging impossible).
// here we assume that self_print is always defined and is always a compiled
// function
print_exception() : any
 -> (let p := use_as_output(stdout),
         %err := system.exception!,
         %prop := ((self_print @ owner(%err)) as method) in
       (try (if known?(functional, %prop)
            funcall(%prop.functional, object, %err, any)
         else funcall(%prop, %err))
        catch any printf("****** ERROR[121]: unprintable error has occurred.\n"),
      use_as_output(p)))

// *********************************************************************
// *     Part 4: the show & kill methods                               *
// *********************************************************************

pretty_show :: property(open = 3)

//----------------- printing an object -------------------------
// %show is an open restriction which allow to show the value of a
// binary relation
//
// this method is the basic method called for show(..)
//
show(self:any) : any
 -> (case self
      (object for rel in owner(self).slots
               printf("~S: ~S\n", rel.selector, get(rel, self)),
       any printf("~S is a ~S\n", self, owner(self))),
     true)

// This is the good version of kill, the nasty one is dangerous ....
// these restrictions of kill explain the dependencies among objects
//
claire/kill(self:object) : any
 -> (case self (thing put(self.name, unknown)),
     write(instances, self.isa, self.isa.instances delete self),
     {})

claire/kill(self:class) : any
 -> (while self.instances kill(self.instances[1]),
     for x in self.descendents (if (x.superclass = self) kill(x)),
     kill@object(self))

// our two very special inline methods
min(x:integer,y:integer) : integer => (if (x <= y) x else y)
max(x:integer,y:integer) : integer => (if (x <= y) y else x)

min(x:float,y:float) : float => (if (x <= y) x else y)
max(x:float,y:float) : float => (if (x <= y) y else x)

min(x:any,y:any) : type[x U y] => (if (x <= y) x else y)
max(x:any,y:any) : type[x U y] => (if (x <= y) y else x)

// this is a useful macro for hashing
[mClaire/hashgrow(l:list,hi:property) : list
 =>  let l1 := l,
         l2 := make_list(nth_get(l1, 0) * 2, unknown) in
       (for x in l1 (if known?(x) hi(l2, x)), l2) ]

// check if the value if known?
known?(a:table,x:any) : boolean => (get(a,x) != unknown)
unknown?(a:table,x:any) : boolean => (get(a,x) = unknown)

float!(self:string) : float
 -> let x := read(self) in
      (case x (float x,
               integer float!(x),                     // v3.3.22
               any error("[??] ~A is not a float",self)))

// v3.00.46 a new macro
>=(self:any,x:any) : boolean => (x <= self)

// v3.3: a recursive macro
;claire/quick_sort(self:list,f:property,n:integer,m:integer) : void
; => (if (m > n)
;        let x := self[n] in
;          (if (m = (n + 1))
;              (if call(f, self[m], x)
;                  (self[n] := self[m], self[m] := x))
;           else let p := (m + n) >> 1, q := n in   // new: p is pivot's position
;                  (x := self[p],
;                   if (p != n) self[p] := self[n],
;                   for p in ((n + 1) .. m)
;                     (if call(f, self[p], x)
;                         (self[n] := self[p],
;                          n := n + 1,
;                          if (p > n) self[p] := self[n])),
;                   self[n] := x,
;                   quick_sort(self, f, q, n - 1),
;                   quick_sort(self, f, n + 1, m))))

// v3.3.42 add macros to use float & integers easily
[+(x:integer,y:float) : float => float!(x) + y]
[*(x:integer,y:float) : float => float!(x) * y]
[/(x:integer,y:float) : float => float!(x) / y]
[-(x:integer,y:float) : float => float!(x) - y]
[+(x:float,y:integer) : float => x + float!(y)]
[*(x:float,y:integer) : float => x * float!(y)]
[/(x:float,y:integer) : float => x / float!(y)]
[-(x:float,y:integer) : float => x - float!(y)]

// v3.4 a useful macro
claire/sqr(x:integer) : integer => (x * x)
claire/sqr(x:float) : float => (x * x)

