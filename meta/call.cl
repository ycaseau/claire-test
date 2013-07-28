//+-------------------------------------------------------------+
//| CLAIRE                                                      |
//| call.cl                                                     |
//| Copyright (C) 1994 - 2003 Yves Caseau. All Rights Reserved  |
//| cf. copyright info in file object.cl: about()               |
//+-------------------------------------------------------------+

// -----------------------------------------------------------------
// This file holds the definition of functional calls in CLAIRE
// -----------------------------------------------------------------`

// *********************************************************************
// * Contents                                                          *
// *      Part 1: the basic object messages                            *
// *      Part 2: Basic structures                                     *
// *      Part 3: Specialized structures                               *
// *      Part 4: Functions on instructions                            *
// *********************************************************************

// *********************************************************************
// *      Part 1: the basic object messages                            *
// *********************************************************************

// contains the last message that was evaluated
iClaire/LastCall:any := unknown

// messages in CLAIRE are called calls --------------------------------
//
Call[selector,args] <: Control_structure(selector:property,args:list)
Call*[selector,args] <: Call()
Call+[selector,args] <: Call()

self_print(self:Call) : void
 -> (let %l := pretty.index,
         %s := self.selector,
         %a := self.args in
       (if (%s % operation & length(%a) = 2)
           printf("~I~I ~S ~I~I", (pretty.index :+ 2), printe(%a[1], %s),
                  %s, lbreak(), printe(%a[2], %s))
        else if (%s = nth)
          (if (length(%a) = 3) printf("~I[~S,~S]", printexp(%a[1], false), %a[2], %a[3])
           else if (length(%a) = 1) printf("~I[]",printexp(%a[1], false))
           else printf("~I[~I]", printexp(%a[1], false),
                       (if (length(%a) = 2) print(%a[2])))) // v3.0.70
        else if (%s = nth= & length(%a) >= 3)
           let a := %a[3],
               o := (case a (Call a.selector)) in
             (if (length(%a) = 4)
                 printf("~I[~S,~S] := ~I~S", printexp(%a[1], false),
                        %a[2], a, lbreak(2), %a[4])
              else if sugar?(%a[1], %a[2], o, (case a (Call a.args[1])))
                 printf("~S[~S] :~S ~I~S", %a[1], %a[2], o, lbreak(2),
                        a.args[2])
              else printf("~S[~S] := ~I~S", %a[1], %a[2], lbreak(2), a))
        else if (%s = assign & %a[1] % property)
           let a := %a[3],
               o := (case a (Call a.selector)) in
             (if sugar?(%a[1], %a[2], o, (case a (Call a.args[1])))
                 printf("~S(~S) :~S ~I~S", %a[1], %a[2], o, lbreak(2),
                        a.args[2])
              else printf("~S(~S) := ~I~S", %a[1], %a[2], lbreak(2), %a[3]))
        else if (%s = add & %a[1] % property)
           printf("~S(~S) :add ~I~S", %a[1], %a[2], lbreak(2), %a[3])
        else if (%s = delete & %a[1] % property)
           printf("~S(~S) :delete ~I~S", %a[1], %a[2], lbreak(2), %a[3])
        else if (%a[1] = system & length(%a) = 1) printf("~S()", %s)
        else printf("~S(~I~I)", %s, set_level(), printbox(%a)),
        pretty.index := %l))

self_print(self:Call+) : any
 -> printf("~I.~S", printexp(self.args[1], true), self.selector)

self_eval(self:Call) : any
 -> (let start := mClaire/index!(),
         p := self.selector in
       (if (system.Core/debug! >= 0) LastCall := self,
        for x in self.args mClaire/push!(eval(x)),
        let rx := eval_message(p, Core/find_which(p, start,
                                                  owner(mClaire/get_stack(start))),
                               start, true) in
          (if (system.Core/debug! >= 0) LastCall := self,
           rx)))

self_eval(self:Call+) : any
 -> (let p := self.selector,
         x := eval(self.args[1]),
         s := (p @ owner(x)) in
       (if not(owner(s) = slot)
            selector_error(selector = p, arg = list(x))  // v3.0.72
        else let z := slot_get(x, (s as slot).index, (s as slot).mClaire/srange) in
               (if (known?(z) | z % s.range)
                   let n := system.Core/trace! in
                     (if (n > 0 &
                          ((p.Core/trace! + system.verbose) > 4 |
                           n = system.Core/step!))
                         (put(Core/trace!, system, 0),
                          printf("read: ~S(~S) = ~S\n", p, x, z),
                          put(Core/trace!, system, n)),
                      z)
                else read_slot_error(arg = x, wrong = p))))

// recursive printing of bicall
//
printe(self:any,s:property) : void
 -> (if (case self
          (Call (self.selector % operation & length(self.args) = 2)))
        (if true printf("(~S)", self) else printexp(self, true))
     else printexp(self, true))

// tells if the sugar :op can be used
//
sugar?(x:any,x2:any,o:any,a:any) : boolean
 -> (case o
      (operation case x
                 (property
                    case a (Call (x = a.selector & a.args[1] = x2), any false)),
      (Variable U global_variable) x = a,
       any case a
                      (Call
                         (a.selector = nth & a.args[1] = x &
                          a.args[2] = x2),
                       any false)))

// *********************************************************************
// *      Part 2: Basic structures                                     *
// *********************************************************************
// ------------------ assignment ---------------------------------------
// <-(var V, arg E) where V is a variable (and therefore NOT a global_variable)
//
// the var slot is filled with a real variable later.

Assign <: Basic_instruction(var:any,arg:any)
self_print(self:Assign) : void
 -> (let a := self.arg,
         o := (case a (Call a.selector)) in
       (if sugar?(self.var, {}, o, (case a (Call a.args[1])))
           printf("~S :~S ~I~I", self.var, o, lbreak(2),
                  printexp(a.args[2], true))
        else printf("~S := ~I~I", self.var, lbreak(2), printexp(a, true)),
        pretty.index :- 2))

self_eval(self:Assign) : any
 -> (if (self.var % Variable)
        write_value((self.var as Variable), eval(self.arg))
     else error("[101] ~S is not a variable", self.var))

// global variables
//
Gassign <: Basic_instruction(var:global_variable,arg:any)
self_print(self:Gassign) : void
 -> (let a := get(arg, self),
         o := (case a (Call a.selector)) in
       (if sugar?(self.var, {}, o, (case a (Call a.args[1])))
           printf("~S :~S ~I~S", self.var, o, lbreak(2), a.args[2])
        else printf("~S := ~I~S", self.var, lbreak(2), a),
        pretty.index :- 2))

self_eval(self:Gassign) : any
 -> (let v := self.var in write_value(v, eval(self.arg)))

//--------------- BOOLEAN OPERATIONS ---------------------------------
// "and" is strictly boolean and is based on short-circuit evaluation.
//
And <: Control_structure(args:list)
self_print(self:And) : void -> printf("(~I)", printbox(self.args, " & "))
self_eval(self:And) : any
 -> not( (for x in self.args (if not(eval(x)) break(true)) ))

// or expression
//
Or <: Control_structure(args:list)
self_print(self:Or) : void -> printf("(~I)", printbox(self.args, " | "))
self_eval(self:Or) : any
 -> (if (for x in self.args (if eval(x) break(true))) true else false)

// ----------------- an anti-evaluator ---------------------------------
//
Quote <: Basic_instruction(arg:any)
self_print(self:Quote) : void  -> printf("quote(~S)", self.arg)
self_eval(self:Quote) : any -> self.arg

// *********************************************************************
// *      Part 3: Specialized structures                               *
// *********************************************************************
// optimized_instruction is the set of optimized messages.
// These are the forms produced by the optimizer. They correspond to basic
// kinds of evaluation.
//
Optimized_instruction <: Complex_instruction()

// This is how a call to a compiled method can be compiled.
// We use the C external function
//
Call_method <: Optimized_instruction(arg:method,args:list)

self_print(self:Call_method) : void
  -> printf("~S(~I)", self.arg, princ(self.args))

self_eval(self:Call_method) : any
  -> (let start := mClaire/index!(), Cprop := self.arg in
        (for x in self.args mClaire/push!(eval(x)),
         execute(Cprop, start, true)))

// same thing with one only argument: we do not use the stack
//
(Call_method1 <: Call_method(),
 self_eval(self:Call_method1) : any
  -> (let f := self.arg,l := self.args in funcall(f, eval(l[1]))) )

// same thing with two arguments
//
(Call_method2 <: Call_method(),
 self_eval(self:Call_method2) : any
  -> (let f := self.arg,
          l := self.args in
        funcall(f, eval(l[1]), eval(l[2]))) )

// an instruction to read a slot
//
Call_slot <: Optimized_instruction(selector:slot,arg:any,test:boolean)
self_print(self:Call_slot) : void
 -> printf("~S(~S)", self.selector, self.arg)
self_eval(self:Call_slot) : any -> get(self.selector, eval(self.arg))

// an instruction to read an array
// selector is an exp with type array, arg is an exp with type integer, and test
// contains the inferred member_type of the array
//
Call_array <: Optimized_instruction(selector:any,arg:any,test:any)
self_print(self:Call_array) : void
 -> printf("~S[~S]", self.selector, self.arg)
self_eval(self:Call_array) : any ->
   nth(eval(self.selector) as array,eval(self.arg) as integer)

// an instruction to read a table
//
Call_table <: Optimized_instruction(selector:table,arg:any,test:boolean)
self_print(self:Call_table) : void
 -> printf("~S[~S]", self.selector, self.arg)
self_eval(self:Call_table) : any ->
  (if self.test self.selector[eval(self.arg)]
   else get(self.selector, eval(self.arg)))

// an instruction to write a slot
// the structure is complex: see ocall.cl
//
Update <: Optimized_instruction(selector:any,
                                arg:any,
                                value:any,
                                var:any)
self_print(self:Update) : void
 -> printf("~S(~S) := ~S", self.selector, self.var.arg, self.value)
self_eval(self:Update) : any
 -> let s := self.selector in
      (case s
        (property put(s, eval(self.var.arg), eval(self.value)),
         table s[eval(self.var.arg)] := eval(self.value)),
       unknown)

// ------------------ SUPER: a jump in the set lattice ---------------
// A "super" allows one to execute a message as if the type of the receiver
// was a given abstract_class.
// However we require that the receiver be in the specified abstract_class.
// The form of the super is: SELECTOR@ABSTRACT_CLASS(RECEIVER , ...)
//
Super <: Control_structure(selector:property,cast_to:type,args:list)

self_print(self:Super) : void
 -> (let %l := pretty.index,
         %s := self.selector,
         %a := self.args in
       (printf("~S@~S(~I~I)", self.selector, self.cast_to, set_level(),
               printbox(%a)),
        pretty.index := %l))

self_eval(self:Super) : any
 -> (let start := mClaire/index!(),
         t := self.cast_to,
         c := class!(t),
         p := self.selector in
       (for x in self.args mClaire/push!(eval(x)),
        eval_message(p, Core/find_which(c, p.Core/definition, start, mClaire/index!()),
                     start, true)))

//--------------- comments ------------------------------------------
// the cast is the new form of simple super
//
Cast <: Basic_instruction(arg:any,set_arg:type)

self_print(x:Cast) : void
 -> printf("~I as ~I", printexp(x.arg, false), printexp(x.set_arg, false))

self_eval(self:Cast) : any
 -> let x := eval(self.arg), y := self.set_arg in
      (if (case y (Param ((y.arg = list | y.arg = set) & y.args[1] % set)))
          Core/check_in(x, bag, ((y as Param).args[1] as set)[1])
       else Core/check_in(x,y))                // v3.3.16

// ----------------- return from a loop --------------------------------
//
// return_error is an exception that is handled by the "for" family
// of structures
//
Return <: Basic_instruction(arg:any)

self_print(self:Return) : void
 -> printf("break(~I~S~I)", (pretty.index :+ 2), self.arg,
           (pretty.index :- 2))
self_eval(self:Return) : any -> return_error(arg = eval(self.arg))

// ****************************************************************
// *       Part 4: Miscellaneous on instructions                  *
// ****************************************************************
// substitute any variable with same name as x with the value val
[substitution(self:any,x:Variable,val:any) : any
 -> case self
      (Variable (if (self.mClaire/pname = x.mClaire/pname) val else self),
       bag (for i in (1 .. length(self))
              (if (self[i] % Variable | self[i] % unbound_symbol)
                  self[i] := substitution(self[i], x, val)
               else substitution(self[i], x, val)),
            self),
       unbound_symbol (if (self.name = x.mClaire/pname) val else self),
       Instruction (for s in owner(self).slots
                      let y := get(s, self) in
                         (if (y % Variable | y % unbound_symbol)
                             put(s, self, substitution(y, x, val))
                          else substitution(y, x, val)),
                    self),
       any self) ]

// count the number of occurrences of x
[occurrence(self:any,x:Variable) : integer
 -> case self
      (Variable (if (self.mClaire/pname = x.mClaire/pname) 1 else 0),
       bag let n := 0 in
             (for i in (1 .. length(self)) n :+ occurrence(self[i], x), n),
       unbound_symbol (if (self.name = x.mClaire/pname) 1 else 0),
       Instruction let n := 0 in
                     (for s in owner(self).slots
                        n :+ occurrence(get(s, self), x),
                      n),
       any 0) ]

// makes a (deep) copy of the instruction self
//
instruction_copy(self:any) : any
 -> (case self
      (bag let l := copy(self) in
             (for i in (1 .. length(self)) l[i] := instruction_copy(self[i]),
              l),
       Variable self,
       Instruction let o := copy(self) in
                     (for s in owner(self).slots
                        put(s, o, instruction_copy(get(s, self))),
                      o),
       any self))




