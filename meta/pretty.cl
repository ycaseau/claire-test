//+-------------------------------------------------------------+
//| CLAIRE                                                      |
//| pretty.cl                                                   |
//| Copyright (C) 1994 - 2003 Yves Caseau. All Rights Reserved  |
//| cf. copyright info in file object.cl: about()               |
//+-------------------------------------------------------------+

// ---------------------------------------------------------------------
// Contents:
//   Part 1: unbound_symbol and variables
//   Part 2: lambdas
//   Part 3: close methods for lattice_set instantiation
//   Part 4: Pretty printing
// ---------------------------------------------------------------------

Instruction <: system_object()
Basic_instruction <: Instruction()

no_eval(self:Instruction) : any
 -> error("[144] evaluate(~S) is not defined", owner(self))

// import
iClaire/typing :: Kernel/typing
iClaire/index :: mClaire/index

// *********************************************************************
// *   Part 1: unbound_symbol and variables                            *
// *********************************************************************

// An unbound_symbol is created by the reader when a symbol is not bound
//
//unbound_symbol <: Basic_instruction(identifier:symbol)
self_print(self:unbound_symbol) : void
   -> printf("~A", self.name)
self_eval(self:unbound_symbol) : any
   -> (if (get(self.name) % thing)  eval(get(self.name))
       else error("[145] the symbol ~A is unbound",  self.name))

// A lexical variable is defined by a "Let" or inside a method's definition
//
// Lexical variables --------------------------------------------------
//
Variable[mClaire/pname,range] <: Basic_instruction(
     mClaire/pname:symbol,              // name of the variable
     range:type,                        //
     index:integer)                     // position in the stack

self_print(self:Variable) : void ->
  (when s := get(mClaire/pname,self) in princ(s) else princ("V?"))

ppvariable(self:Variable) : void
 -> (if known?(range, self)
        printf("~A:~I", self.mClaire/pname, printexp(self.range, false))
     else princ(self.mClaire/pname))

ppvariable(self:list) : void
 -> (let f := true in
       for v in self
         (if f f := false
          else princ(","),
          case v (Variable ppvariable(v), any print(v))))

self_eval(self:Variable) : any -> mClaire/get_stack(mClaire/base!() + self.index)

write_value(self:Variable,val:any) : any
 -> (if (unknown?(range, self) | val % self.range)
        mClaire/put_stack(mClaire/base!() + self.index, val)
     else range_error(arg = self, cause = val, wrong = self.range))

// this is the definition of a typed variable
//
Vardef <: Variable()
self_eval(self:Vardef) : any
  ->  (when i := get(index,self) in mClaire/get_stack(mClaire/base!() + i)
       else error("[146] The variable ~S is not defined",self))

//   [self_print(self:Vardef) : any -> ppvariable(self) ]
Complex_instruction <: Instruction()
Instruction_with_var <: Complex_instruction(var:Variable)
Control_structure <: Complex_instruction()

// global_variables are defined in exception ? ---------------------------
// a global variable is a named object with a special evaluation
//
self_eval(self:global_variable) : any -> self.value
write_value(self:global_variable,val:any) : any
 -> (if (val % self.range)
        (put_store(value,self,val,self.store?), val)
     else range_error(cause = self, arg = val, wrong = self.range)) // v0.01

(put(mClaire/evaluate, global_variable, function!(self_eval_global_variable)),
 put(mClaire/evaluate, unbound_symbol, function!(self_eval_unbound_symbol)))

// same as C
EOF :: global_variable(range = char, value = char!(externC("((int) EOF)",integer))) // v3.2.52
EOS :: global_variable(range = char, value = char!(0))

// v3.4
claire/MAX_INTEGER :: 1073741822

// *********************************************************************
// *   Part 2: CLAIRE Lambdas                                           *
// *********************************************************************

// CLAIRE lambdas are the basic functional objects, defined by a filter
// and a piece of code. Lambda is defined in the "method" file.
// applying a lambda to a list of arguments
//
apply(self:lambda,%l:list) : any
 -> (let start := mClaire/index!(),
         retour := mClaire/base!() in
       (mClaire/set_base(start),
        for %x in %l mClaire/push!(%x),
        mClaire/stack_apply(self.dimension),
        let val := eval(self.body) in
          (mClaire/set_base(retour), mClaire/set_index(start), val)))
call(self:lambda,l:listargs) : any -> apply(self, l)

// printing a lambda
//
self_print(self:lambda) : any
 -> printf("lambda[(~I),~I~S~I]", ppvariable(self.vars), lbreak(1),
           self.body, (pretty.index :- 1))

// lambda! and flexical_build communicate via a global_variable, which
// however is only used in this file (and also by cfile :-) ):
//
*variable_index* :: global_variable(range = integer, value = 0)

// creating a lambda from an instruction and a list of variables
lambda!(lvar:list,self:any) : lambda
 -> (*variable_index* := 0,
     for v:Variable in lvar
       (put(index, v, *variable_index*),
        put(isa, v, Variable),
        *variable_index* :+ 1),
     let corps := lexical_build(self, lvar, *variable_index*),
         resultat:lambda := mClaire/new!(lambda) in
       (put(vars, resultat, lvar),
        put(body, resultat, corps),
        put(dimension, resultat, *variable_index*),
        resultat))

// Give to each lexical variable its right position in the stack.
// We look for a named object or an unbound symbol to replace by a lexical
// variable.
// The number of variables is kept in the global_variable *variable_index*.
// On entry, n need not be equal to size(lvar) (see [case ...instruction]).
//
lexical_build(self:any,lvar:list,n:integer) : any
 -> (if (self % thing | self % unbound_symbol) lexical_change(self, lvar)
     else (case self
            (Variable (if unknown?(index,self)                          // v3.1.12
                          error("[145] the symbol ~A is unbound",  self.mClaire/pname),
                       self),
             Call let s := lexical_change(self.selector, lvar) in
                    (lexical_build(self.args, lvar, n),
                     if (self.selector != s)
                        (put(selector, self, call),
                         put(args, self, s cons self.args))),
             Instruction let %type:class := self.isa in
                           (if (%type % Instruction_with_var.descendents)
                               (put(index, self.var, n),
                                n := n + 1,
                                if (n > *variable_index*)
                                   *variable_index* := n),
                            for s in %type.slots
                              let x := get(s, self) in
                                (if ((x % thing | x % unbound_symbol) &
                                     s.range = any)
                                    put(s, self, lexical_change(x, lvar))
                                 else lexical_build(x, lvar, n))),
             bag let %n := length(self) in
                   while (%n > 0)
                     (let x := (nth@list(self, %n)) in
                        (if (x % thing | x % unbound_symbol)
                            nth=@list(self, %n, lexical_change(x, lvar))
                         else lexical_build(x, lvar, n)),
                      %n :- 1),
             any nil),
           self))

lexical_change(self:any,lvar:list) : any
 -> (let rep:any := self,
         %name:symbol := (case self  (Variable self.mClaire/pname,
                                      any extract_symbol(self))) in
       (for x:Variable in lvar (if (x.mClaire/pname = %name) rep := x), rep))

// *******************************************************************
// *       Part 3: functions for lattice_set instantiation           *
// *******************************************************************
// close is the basic method called by an instantiation.
// Once the indexed list is built, we never call it again.
//
close(self:class) : class -> self

// Extract the symbol associated with self.
// This is useful e.g. when using read() (read@port, read@string).
//
extract_symbol(self:any) : symbol
 -> (case self
      (unbound_symbol self.name,
       thing self.name,
       class self.name,
       symbol self,
       Variable self.mClaire/pname,
       boolean (if self symbol!("true") else symbol!("nil")),
       any error("[147] a name cannot be made from ~S", self)))

// we must be sure that the selector (in a has statement or in a message)
// is a property.
//
make_a_property(self:any) : property
 -> (case self
      (global_variable make_a_property(value(self)),
       property self,
       symbol let x := get(self) in
               (case x (property make_a_property(x),
                        global_variable  make_a_property(value(x)),
                        any  let p := (mClaire/new!(property, self) as property) in
                                 (p.comment := string!(self),
                                  put(domain, p, any),
                                  put(range, p, any),
                                  p))),
       unbound_symbol make_a_property(self.name),
       any error("[148] Wrong selector: ~S, cannot make a property\n", self)))

printl :: property()

// *********************************************************************
// *  Part 4: Pretty printing                                          *
// *********************************************************************

// fuck
lbreak() : any
 -> (if pretty.mClaire/pprint
        (if (pretty.mClaire/pbreak)
            (princ("\n"),
             put_buffer(),
             indent(pretty.index))
         else if (mClaire/buffer_length() > pretty.mClaire/width)  much_too_far()))

put_buffer() : any
 -> (let buffer := end_of_string() in
       (princ(buffer), print_in_string(), {}))

checkfar() : any
 -> (if (pretty.mClaire/pprint & not(pretty.mClaire/pbreak) &
         mClaire/buffer_length() > pretty.mClaire/width) much_too_far())

lbreak(n:integer) : any -> (pretty.index :+ n, lbreak())

// indentation
//
indent(limit:integer) : any
 -> (let x := mClaire/buffer_length() in while (x < limit) (princ(" "), x :+ 1))

// sets the current_level
set_level() : void
 -> (pretty.index := mClaire/buffer_length() - 1)
set_level(n:integer) : void -> (set_level(), pretty.index :+ n)

// prints a bag as a box
//
printbox(self:bag,start:integer,finish:integer,s:string) : any
 -> (let i := 1,
         startline := true,
         n := length(self),
         %l := pretty.index in
       (pretty.index := start,
        if (not(pretty.mClaire/pprint) | (not(short_enough(start + 10))
             & pretty.mClaire/pbreak))
           printl(self, s)
        else if not(pretty.mClaire/pbreak) printl(self, s)
        else while (i <= n)
               (while (Core/buffer_length() < start) printf(" "),
                let idx := Core/buffer_length() in
                  (try (pretty.mClaire/pbreak := false,
                        printexp(self[i], true),
                        pretty.mClaire/pbreak := true)
                   catch much_too_far (pretty.mClaire/pbreak := true,
                                       pretty.index := start),
                 if (i != n) princ(s),
                 if (Core/buffer_length() < finish)
                    (i :+ 1, startline := false)
                 else (Core/buffer_set_length(idx),
                       if not(startline) (lbreak(), startline := true)
                       else (set_level(),
                             pretty.index :+ 1,
                             printexp(self[i], true),
                             pretty.index := %l,
                             if (i != n) (princ(s), lbreak()),
                             i :+ 1)))),
        pretty.index := %l,
        unknown))

// default value of arguments
//
printbox(self:bag) : any
 -> printbox(self, mClaire/buffer_length(), pretty.mClaire/width, ", ")
printbox(self:bag,s:string) : any
 -> printbox(self, mClaire/buffer_length(), pretty.mClaire/width, s)
printl(self:bag,s:string) : void
 -> (let f := true,
         b := pretty.mClaire/pprint in
       (pretty.mClaire/pprint := false,
        try for x in self
          (if f f := false
           else princ(s),
           printexp(x, true),
           if (b & not(pretty.mClaire/pbreak) &
                   mClaire/buffer_length() > pretty.mClaire/width)
              (pretty.mClaire/pprint := b, much_too_far()))
        catch system_error let x := (system.exception! as exception) in
                             (if (b & x.index = 16)
                                 (pretty.mClaire/pprint := b, much_too_far())
                              else close(x)),
      pretty.mClaire/pprint := b))

// print bounded prints a bounded expression using ( and )
[printexp(self:any,comp:boolean) : void
 ->  if ((case self
           (Call not((self.selector % operation & not(comp) &
                      length(self.args) = 2)))) |
         self % Collect | self % Select | self % Definition |
         self % Construct | self % Do | self = unknown | self % And |
         self % import | self % Or | self % If | self % restriction |
         self % unbound_symbol | self % Variable | not(self % Instruction)) print(self)
     else let %l := pretty.index in
            (printf("(~I~S)", set_level(1), self), pretty.index := %l) ]

pretty_print(self:any) : void
 -> (print_in_string(),
     pretty.mClaire/pprint := true,
     pretty.mClaire/pbreak := true,
     pretty.index := 0,
     print(self),
     pretty.mClaire/pprint := false,
     princ(end_of_string()))

[self_print(self:list) : void
 -> if (of(self) != {}) printf("list<~S>",of(self)),
    printf("(~I)", printbox(self)) ]

[self_print(self:set) : void
  -> if (of(self) = {}) printf("{~I}", printbox(self))
     else  (printf("set<~S>",of(self)),
            printf("(~I)", printbox(self))) ]  

// to remove !
[self_print(self:tuple) : void
 -> printf("tuple(~I)", printbox(self)) ]


// bend of file
