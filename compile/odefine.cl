//+-------------------------------------------------------------+
//| CLAIRE                                                      |
//| odefine.cl                                                  |
//| Copyright (C) 1994 - 2003 Yves Caseau. All Rights Reserved  |
//| cf. copyright info in file object.cl: about()               |
//+-------------------------------------------------------------+

// *********************************************************************
// *  Table of contents                                                *
// *     Part 1: Set, List and Tuple creation                          *
// *     Part 2: Object definition                                     *
// *     Part 3: Method instantiation                                  *
// *     Part 4: Inverse Management                                    *
// *********************************************************************

// *********************************************************************
// *     Part 1: Set, List and Tuple creation                          *
// *********************************************************************

// type inference has changed in v3.2:
c_type(self:List) : type
 -> (//[5] call c_type with ~S -> ~S // self, get(of,self),
     if known?(of,self) Core/param!(list,self.of)
     else let %res:any := {} in
            (for %x in self.args
               (if %res %res :meet class!(ptype(c_type(%x)))     // v3.3 : use ptype !
                else %res := class!(ptype(c_type(%x)))),
             nth(list,%res)))

// compile a List: take the of parameter into account !
[c_code(self:List) : any
 -> OPT.allocation := true,
    let x := List(args = list{ c_gc!(c_code(%x,any), c_type(%x)) |
                                        %x in self.args}) in
       (if known?(of,self)
          (if (compiler.safety > 4 | self.of = {} |
               forall(%x in self.args | c_type(%x) <= self.of))
              (x.of := self.of, x)
           else (warn(),
                 trace(2,"unsafe typed list: ~S not in ~S [262]\n",
                       list{c_type(%x) | %x in self.args}, self.of),
                 c_code( Call(Core/check_in,list(x,list,self.of)), list)))
        else x) ]

// new in v3.2: static list have type inference !         
c_type(self:Set) : type
 -> (//[5] call c_type with ~S -> ~S // self, get(of,self),
     if known?(of,self) Core/param!(set,self.of)
     else let %res:any := {} in
           (for %x in self.args
               (if %res %res :meet class!(c_type(%x))
                else %res := class!(c_type(%x))),
             nth(set,%res)))

[c_code(self:Set) : any
 ->  OPT.allocation := true,
     let x := Set(args = list{ c_gc!(c_code(%x,any), c_type(%x)) |
                               %x in self.args}) in
        (if known?(of,self)
          (if (compiler.safety > 4 | self.of = {} |
               forall(%x in self.args | c_type(%x) <= self.of))
              (x.of := self.of, x)     // the set expression is type safe
           else (warn(),
                 trace(2,"unsafe typed set: ~S not in ~S [262]\n",
                       list{c_type(%x) | %x in self.args}, self.of),
                 c_code( Call(Core/check_in,list(x,set,self.of)), set)))
         else x) ]

[c_type(self:Tuple) : type -> tuple!(list{c_type(x) | x in self.args}) ]

[c_code(self:Tuple) : any
 -> OPT.allocation := true,
    Tuple(args = list{ c_gc!(c_code(%x,any), c_type(%x)) |%x in self.args}) ]


// ******************************************************************
// *      Part 2: Compiling Definitions                             *
// ******************************************************************

c_type(self:Definition) : type ->
  (if (self.arg Core/<=t exception) {} else self.arg)

Compile/*name*:symbol := symbol!("_CL_obj")     // */

// creation of a new object
//
c_code(self:Definition,s:class) : any
 -> (let %c := self.arg,
         %v:Variable := Variable!(*name*, (OPT.max_vars :+ 1, 0), %c),
         %x := total?(%c, self.args) in
       (if (%c.open <= 0) error("[105] cannot instantiate ~S", %c),     // v3.2.44
        if %x c_code(%x, s)
        else c_code(Let(var = %v,
                        value = Cast(arg = c_gc!(c_code(Call(mClaire/new!, list(%c)), object)),
                                     set_arg = %c),
                        arg = Do(args = analyze!(%c, %v, self.args, list()))),
                    s)))

// tells if a "total instantiation" is appropriate (for exceptions)
// we actually check that the srange is OID or integer for all slots
[total?(self:class,l:list) : any
 ->  let lp := get_indexed(self),
         n := length(lp) in
       (if (not(compiler.diet?) & length(l) = n - 1 & 
            (self.open = ephemeral() | self Core/<=t exception) &
            n <= 4 & forall(i in (2 .. n) | srange(lp[i]) % {any,integer}))
         let %c:any := Call((if (length(l) = 0) mClaire/new! else anyObject!),
                        self cons list{ c_gc!(c_code(x.args[2],any)) | x in l}),  // v3.00.10
             m := (close @ self) in
           (if not(self <= exception) OPT.allocation := true,                    // v3.2.32 !
            if (length(l) = 0) %c := c_code(%c),
            if m Call_method1(arg = m, args = list(%c)) else %c)
        else false) ]


// the instantiation body is a sequence of words from which the initialization
// of the object must be built. This method produces a list of CLAIRE instructions
// self is the object (if named) or a variable if unamed
// [in ClReflect.cpp] we create an object from prototype = list of OK defaults
// OK defaults = object (for object) + float (for float) + integer (for anything)
//               + NULL for objects
[analyze!(c:class,self:any,%l:list,lp:list) : any
 -> let ins?:boolean := (c.open != 4 & not(lp) & not(compiler.class2file?)), // PATCH!
        r := list<any>{ (let p := x.args[1], y := x.args[2],
                             s := (p @ c), special? := (p.open = 0 & s % slot) in
                       (lp :add p,
                        Call((if special? put else write),
                                  list(p, self,
                                    (if (not(special?) | c_type(y) <= s.range) y
                                     else c_check(c_code(y, any),
                                                  c_code(s.range, type))))))) |
                      x:Call in %l} in
       (if ins? r :add Call(selector = add, args = list(instances, c, self)),
        if not(compiler.class2file?)      // otherwise the constructor takes care of it
          for s:slot in get_indexed(c)
          let p := s.selector,
              v := get(default, s) in
            (if (known?(v) & (if multi?(p) v else true) & not(p % lp) &
                 (known?(inverse, p) | known?(Kernel/if_write, p) |
                  (srange(s) != object & srange(s) != float & not(v % integer))))
               let defExp := (if designated?(v) v // v3.0.43, was: c_code(v,any) // ?? NEW
                              else Call(default, list(Cast(arg = Call(@,list(p, c)),
                                                           set_arg = slot)))) in
                r :add
                  // REMOVED AS WELL (if (srange(s) = float) Call(mClaire/update,list(p,self,s.index,float,defExp))
                    Call(write,list(p,self,defExp))),
        let m := (close @ c) in
          r :add (if m Call_method1(arg = m, args = list(self)) else self),
        r) ]

// creation of a new named object
c_code(self:Defobj,s:class) : any
 -> let %a := OPT.allocation,
        %c := self.arg, o := get(self.Language/ident),
        %v := (if (known?(o) & not(o % global_variable)) o
               else Variable!(*name*, (OPT.max_vars :+ 1, 0), %c)),
        %y1 := Call(object!, list(self.Language/ident, %c)),
        %y2 := analyze!(%c, %v, self.args, list(name)),
        %x:any := (if not(%v % Variable) Do(%y1 cons %y2)
                   else  Let(var = %v, value = %y1, arg = Do(%y2))) in
       (//[5] compile defobj(~S) -> ~S // self, o,
        if (%c.open <= 0) error("[105] cannot instantiate ~S", %c),          // v3.2.44
        if known?(o)
           (if not(o % OPT.objects)
               (OPT.objects :add o, c_register(o)))
        else (warn(),trace(2, "~S is unknown [265]\n", self.Language/ident)),
        %x := c_code(%x, s),
        if (self.arg <= exception) OPT.allocation := %a,          // v3.2.24 : no GC for exceptions
        %x)

// creation of a new named object
[c_code(self:Defclass,s:class) : any
 -> let  %name := self.Language/ident, o := get(%name),
         %create := (if known?(o) Call(class!, list(%name, self.arg))
                     else error("[internal] cannot compile unknown class ~S",%name)),
         %x := Do( %create cons
                  (list{ (let v := unknown in       // default value
                          (case x (Call (v := x.args[2], x := x.args[1])),
                           Call(add_slot,
                                list(o, Language/make_a_property(x.Core/pname),
                                     x.range, v, 0)))) |     // v3.2 add index 0
                              x in self.args} /+
                  (if self.params
                      list(Call(put, list(params, o, self.params)))
                   else list()))) in
       (if not(o % OPT.objects)
         (OPT.objects :add o, c_register(o)),
        c_code(%x, s)) ]


claire/SHIT:any :: 1

// method definition
//
c_type(self:Defmethod) : type -> any
[c_code(self:Defmethod) : any
 -> let px := self.arg.selector,
        l := self.arg.args,
        lv := (if (length(l) = 1 & l[1] = system) list(Variable!(*name*, 0, void))
               else l),
        ls := extract_signature!(lv),
        lrange := Language/extract_range(self.set_arg, lv, LDEF),
        sdef:any := (if (self.inline? & compiler.inline?)
             (print_in_string(),
              printf("lambda[(~I),~S]", Language/ppvariable(lv), self.body),
              end_of_string())),
        lbody := extract_status_new(self.body),    // reuse the method from define.cl
        getm := (px @ ls[2]),
        m:method := (case getm (method getm,
                     any error("[internal] the method ~S @ ~S is not known",px,ls[2]))),
        olds := get(status, m) in
     (lbody[2] := get(functional,m),
      if (not(compiler.inline?) & (px = Iterate  | px = iterate)) nil
      else if (lrange[1] = void & sort_pattern?(lv,self.body)) sort_code(self,lv)                         // v3.3
      else (if (lbody[3] != body)
             let na := function_name(px, ls[2], lbody[2]),
                 la := Language/lambda!(lv, lbody[3]),
                 news := (if OPT.recompute c_status(la.body,la.vars)
                          else status!(m)) in
             (compile_lambda(na, la, m),
              if (unknown?(lbody[1]) | OPT.recompute)
                 (if (not(OPT.use_nth=) & news[BAG_UPDATE]) news :- ^2(BAG_UPDATE),
                  if (not(OPT.use_update) & news[SLOT_UPDATE]) news :- ^2(SLOT_UPDATE),
                  if (not(OPT.allocation) & news[NEW_ALLOC]) news :- ^2(NEW_ALLOC),
                     trace(4,"---- CHANGE: status(~S)= ~S to ~S\n",m,olds,news),
                  lbody[1] := news),
              lbody[2] := make_function(na)),
            if (self.set_arg % global_variable) lrange[1] := self.set_arg
            else if (m.range % class & not(lrange[1] % class)) lrange[1] := m.range,
            let %m := add_method!(m, ls[1], lrange[1], lbody[1], lbody[2]) in
                c_code((if (self.inline? & compiler.inline? & not(compiler.diet?))
                           Call(inlineok?, list(%m, sdef))
                        else if (lrange[2] & not(compiler.diet?))
                           let na := (function_name(px, ls[2], lbody[2]) /+
                                        "_type") in
                             (compile_lambda(na, lrange[2], type),
                              Call(write, list(typing, %m, make_function(na))))
                        else %m)))) ]


// v3.3 : we optimize a single sort definition -----------------------------------------------
// [foo(x:list) : list -> sort(m,x) ]
[sort_pattern?(lv:list,%body:any) : boolean
  -> ( (length(lv) = 1) &
       (case %body (Call (%body.selector = sort &
                          (let a1 := %body.args[1] in
                             (case a1 (Call (a1.selector = @ & a1.args[1] % property)))) &
                          lexical_build(%body.args[2],lv,0) = lv[1]),
                    any false))) ]



// this is the macroexpansion of the quick_sort which is difficult because of the dual recursion
// Thus, we generate two methods for one definition, and produce the explicit code for the specialized
// quicksort (v3.3)
[sort_code(self:Defmethod, lv:list) : any
  -> let l := lv[1], f := self.body.args[1].args[1],           // sort_pattern(self) = true !
         m := Variable!(symbol!("m"), 0, integer),
         n := Variable!(symbol!("n"), 0, integer),
         x := Variable!(symbol!("x"), 0, member(l.range)),
         p := Variable!(symbol!("p"), 0, integer),
         q := Variable!(symbol!("q"), 0, integer),
         def1 := Defmethod(arg = self.arg,  inline? = false,  set_arg = self.set_arg,
                           body = Call(self.arg.selector,
                                       list(1, Call(length, list(lv[1])), l))),
         %bd := If(test = Call(>, list(m,n)),
                   arg = Let(var = x, value = Call(nth,list(l,n)),
                             arg = If(
                       test = Call(=,list(m,Call(+,list(n,1)))),
                       arg = If(test = Call(f,list(Call(nth,list(l,m)), x)),
                                arg = Do(list(Call(nth=,list(l,n,Call(nth,list(l,m)))),
                                              Call(nth=,list(l,m,x))))),
                       other = Let(var = p, value = Call(>>,list(Call(+,list(n,m)), 1)),
                                   arg = Let(var = q, value = n,
                                             arg = Do(list(
                          Assign(var = x, arg = Call(nth,list(l,p))),
                          If(test = Call(!=,list(p,n)),
                             arg = Call(nth=,list(l,p,Call(nth,list(l,n))))),
                          For(var = p, set_arg = Call(..,list(Call(+,list(n,1)),m)),
                              arg = If(test = Call(f,list(Call(nth,list(l,p)),x)),
                                       arg = Do(list(Call(nth=,list(l,n,Call(nth,list(l,p)))),
                                                     Assign(var = n, arg = Call(+,list(n,1))),
                                                     If(test = Call(>,list(p,n)),
                                                        arg = Call(nth=,list(l,p,Call(nth,list(l,n))))))))),
                          Call(nth=,list(l,n,x)),
                          Call(self.arg.selector, list(q,Call(-,list(n,1)),l)),
                          Call(self.arg.selector, list(Call(+,list(n,1)),m,l))))))))),
         def2 := Defmethod(arg = Call(self.arg.selector, list(n,m,l)),
                           inline? = false,  set_arg = self.set_arg,
                           body = %bd) in
       (//[2] ---- note: quick sort optimisation for ~S ---- // self.arg.selector,
        eval(def2),                    // we need the method in the system
        Do(list(c_code(def1),
                c_code(def2)))) ]

// new: we deal with floats --------------------------------------

// create a restriction so that OPT is happy
add_method(p:property,ls:list,rg:type,st:integer,f1:function,f2:function) : method
  -> add_method(p,ls,rg,st,f1)

[add_method!(m:method,ls:list,rg:any,stat:any,fu:function) : any
  -> let %c :=  Call_method(arg = (add_method @ property),
                            args =  list(c_code(m.selector,property),
                                         c_code(ls,list),
                                         c_code(rg,type), stat, fu)) in
       (if (m.range = float | float % m.domain | m.range % tuple)
           %c.args :add make_function(string!(fu) /+ "_"),
        %c) ]

extract_status_new(x:any) : list
 -> (let s := unknown,
         f := (if (case x (Call x.selector = function!)) x else unknown) in
       (case x
         (And let y := x.args[1] in
                (if (case y (Call y.selector = function!))
                    (f := y, x := x.args[2])),
          Call (if (x.selector = function!) x := body)),
        if known?(f)
           (x := body,
            if (length(f.args) > 1)(try s := integer!({eval(u) | u in cdr(f.args)}
                                                      as set<integer>)
                                    catch any (warn(),
                                               SHIT := cdr(f.args),
                                               trace(2,"wrong status ~S -> ~S [266]\n",
                                                        f,set!(cdr(f.args))),
                                               s := 0))
            else s := 0,
            f := make_function(string!(extract_symbol(f.args[1])))),
        list(s, f, x)))

// this signature extraction is more subtle since it also builds an external
// list. (l1 is the domain (may use global variables), l2 is the "pure"
// list of patterns)
[extract_signature!(l:list) : list
 -> LDEF := list<any>(),
    let n := 0,
        l1 := list<type>(),    // v3.2.18
        l2 := list<any>{ (let p := Language/extract_pattern(v.range, list(n)) in
                        (n :+ 1,
                         l1 :add! (if (v.range % global_variable) v.range else p),
                         put(range, v, Language/type!(p)),
                         p)) |
                     v:Variable in l} in
      list(l1, l2) ]

// check signature equality
=sig? :: operation()
=sig?(x:list,y:list) : boolean -> (tmatch?(x, y) & tmatch?(y, x))

// creates a name for a restriction from the full domain
// Note that we suppose that a new restriction is not allowed to be inserted
// in a list of restrictions when the property is closed.
//
function_name :: property(open = 3)
[function_name(p:property,l:list,x:any) : string
 -> if (x % function) string!(x as function)
    else let n := 0,
              m := 0,
              md := module!(name(p)),
              c := class!(l[1]),
              r:string := ((string!(p.name) /+ "_") /+ string!(c.name)) in
            (if (compiler.naming = 0 & p != main)     // v3.1.04
               r := (string!(md.name) /+ "_") /+ r,
             for r in p.restrictions
               (if (c = domain!(r)) n :+ 1, if (l =sig? r.domain) m := n),
             r := (if (n <= 1) r else r /+ string!(m)),
             if (stable?(p) | p = main) r                         // important main is NOT qualified !
             else (r /+ "_") /+ string!(module!().name)) ]

// this compiles a lambda into a C method with name oself.
// the use_new flag will be raised if a new object is created inside the
// function.
// m is either the associated method,or the expected range
//
compile_lambda(self:string,l:lambda,m:any) : any
 -> let x := compiler.safety,y := l in
       (trace(3, "---- Compiling ~A,\n", self),
        case m (method OPT.in_method := m),
        OPT.protection := false,
        OPT.allocation := false,
        if (OPT.loop_index > 0) OPT.loop_index := 0,
        OPT.loop_gc := false,
        OPT.use_update := false,
        OPT.use_nth= := false,
        OPT.use_string_update := false,                    // v3.3.46
        OPT.max_vars := 0,
        if (m % OPT.unsure) compiler.safety :=  1,
        make_c_function(l, self, m),
        OPT.in_method := unknown,
        compiler.safety := x,
        true)

// how to compile an table definition
//
[c_code(self:Defarray) : any
 -> let a := (self.arg as Call).args,
        %a := get(extract_symbol(a[1])),
        %v := (case %a (table %a, any error("[internal] the table ~S is unknown", a[1]))),
        s := %a.domain,
        e := (let l := cdr(a),
                  b := Language/lexical_build(self.body, l, 0) in
                (if exists(va in l | Language/occurrence(b, va) > 0) lambda!(l, b)
                 else self.body)),
        d := (case e (lambda unknown, any self.body)),
        %l1 := (if %a.multivalued?
                   list<any>(Call(put, list(multivalued?, %v, %a.multivalued?)))
                else list<any>()),
        %l2 := list<any>(Call(put, list(range, %v, %a.range)),
                         Call(put, list(params, %v, %a.params)),
                         Call(put, list(domain, %v, s))) in
       (put(range, (a[2] as Variable),
            Language/extract_type((a[2] as Variable).range)),
        if (length(a) = 2)
           (%l2 :add
              Call(put,
                   list(Kernel/graph, %v,
                          (case s
                            (Interval Call(make_copy_list, list(size(s), d)),
                             any Call(make_list, list(29, unknown)))))),
            %l2 :add
              (case e
                (lambda For(var = a[2], set_arg = s,
                            arg = Call(nth=, list(%v, a[2], e.body))),
                 any Call(selector = put, args = list(default, %v, d)))))
        else let s2 := extract_type((a[3] as Variable).range) in
               (put(range, (a[3] as Variable), s2),
                %l2 :add
                  Call(put,
                       list(Kernel/graph, %v,
                              Call(make_copy_list,
                                   list(length(%a.Kernel/graph),
                                          (if (%a.params = any) unknown
                                           else %a.default))))),
                %l2 :add
                  (case e
                    (lambda
                       For(var = a[2], set_arg = s[1],
                           arg =
                             For(var = a[3], set_arg = s2,
                                 arg = Call(nth=, list(%v, a[2], a[3], e.body)))),
                     any Call(put, list(default, %v, d))))),
        OPT.objects :add %a,
        c_register(%a),
        c_code(Do( Call( object!, list(%a.name, table)) cons (%l1 add* %l2)),
               any)) ]


// *********************************************************************
// *     Part 4: Inverse Management (new in v3.0.50)                   *
// *********************************************************************


// this method creates an if_write demon that takes care of the inverse
Compile/compute_if_write_inverse(R:relation) : void
 -> let x := Variable(pname = symbol!("XX"), range = R.domain),
         y := Variable(pname = symbol!("YY"), range = (if multi?(R) member(R.range) else R.range)),
         z := Variable(pname = symbol!("ZZ"), range = R.range),
         l1 := list<any>() in
     (if multi?(R)
         (// generate an if_write demon that does the add!
          l1 := list<any>(Produce_put(R,x,y)),
          if known?(inverse,R)
            l1 :add Produce_put(R.inverse,y,x),
          R.if_write := lambda!(list(x,y),
                                If(test = Call(not, list(Call(%, list(y,Produce_get(R,x))))),
                                   arg = Do(l1))))
      else (//generate an if_write demon that does the put
            l1 := list<any>(Produce_put(R,x,y)),
            if known?(inverse,R)
               (l1 :add If(test = Call(known?, list(z)),
                           arg = Produce_remove(R.inverse,z,x)),
                l1 :add Produce_put(R.inverse,y,x)),
            R.if_write := lambda!(list(x,y),
                                  Let(var = z,
                                      value = Produce_get(R,x),
                                      arg = If(test = Call(!=,list(y,z)),
                                      arg = Do(l1))))),
      let dn := string!(R.name) /+ "_write" in
          (Compile/compile_lambda(dn, R.if_write, void)))

// generate a demon to perform x.R := s (s is a set)
Compile/compute_set_write(R:relation) : any
 -> let x := Variable(pname = symbol!("XX"), range = R.domain),
        y := Variable(pname = symbol!("YY"), range = bag),
        z := Variable(pname = symbol!("ZZ"), range = member(R.range)),
       l1 := list<any>() in
     (//[0] compute set_write for ~S // R,
      if known?(inverse,R)
         l1 :add For(var = z, set_arg = Produce_get(R,x),
                     arg = Produce_remove(R.inverse,z,x)),
      l1 :add Produce_erase(R,x),
      l1 :add For(var = z, set_arg = y,
                  arg = Produce_put(R,x,z)),
      let dn := string!(R.name) /+ "_set_write" in
          Compile/compile_lambda(dn, lambda!(list(x,y),Do(l1)), void))

// generate a simple put for a property => generate a case to make sure
// that we get the fastest possible code
Compile/Produce_put(r:property,x:Variable,y:any) : any
  -> let l := list<any>() in
       (for xs in {xs in r.restrictions | (xs % slot & ptype(x.range) ^ domain!(xs)) }
          l :add* list(domain!(xs),
                       (if r.multivalued? Call(add!,
                                           list(Call(r, list(Cast(arg = x, set_arg = domain!(xs)))), y))
                        else Call(put, list(r,Cast(arg = x, set_arg = domain!(xs)), y)))),
        if (length(l) = 2) l[2]
        else Case(var = x, args = l))

// generate a simple erase (the inverse management has been done)
// v3.2.50: use ptype(x.range) for variable whose type is t U any :-)
Compile/Produce_erase(r:property,x:Variable) : any
  -> let l := list<any>(),
         val := (if (r.multivalued? = list) list<any>() else set<any>()) in
       (cast!(val,member(r.range)),
        for xs in {xs in r.restrictions | (xs % slot & ptype(x.range) ^ domain!(xs)) }
          l :add* list(domain!(xs),
                       Call(put, list(r,Cast(arg = x, set_arg = domain!(xs)),
                                        (if r.multivalued? val else xs.default)))),  // v3.2.50
        if (length(l) = 2) l[2]
        else Case(var = x, args = l))

// note:  (a) Simpler because of v3.0 !! (siude-effects on lists or sets)
//        (b) if |l|= 1 domain!(r) = domain!(x) because of tighten

// same for a table
Compile/Produce_put(r:table,x:Variable,y:any) : any
 -> Call(put, list(r,x,
                   (if r.multivalued? Call(add,list(list(nth,list(r,x)), y))
                    else y)))

  
Compile/Produce_get(r:relation,x:Variable) : any
 -> (case r (table  Call(nth, list(r,x)),
             property   let l := list<any>() in
                          (for xs in {xs in r.restrictions |
                                      (xs % slot & ptype(x.range) ^ domain!(xs)) }
                             l :add* list(domain!(xs),
                                          Call(r, list(Cast(arg = x, set_arg = domain!(xs))))),
                           if (length(l) = 2) l[2]
                           else Case(var = x, args = l))))
 
// generate a remove
Compile/Produce_remove(r:property,x:Variable,y:any) : any
  -> let l := list<any>() in
       (for xs in {x in r.restrictions | x % slot}
        l :add* list(domain!(xs),
                     (if r.multivalued? Call(delete,list(Call(r,list(x)),y))
                      else Call(put, list(r,x,unknown)))),
        if (length(l) = 2) l[2]
        else Case(var = x, args = l))

// same for a table
Produce_remove(r:table,x:Variable,y:any)  : any
 -> Call(put, list(r,x,
                   (if r.multivalued? Call(delete,list(list(nth,list(r,x)), y))
                    else unknown)))


Compile/Tighten(r:relation) : void
  -> (case r (property
                 let ad:type := set(), ar:type := set() in
                   (for s in {x in r.restrictions | x % slot}
                      (ad :U domain!(s),
                       ar :U (if multi?(r) member(s.range) else s.range)),
                    r.open := 1,
                    put(domain,r,class!(ad)),
                    put(range,r,
                         (if (r.multivalued? = list) Core/param!(list,class!(ar))
                          else if (r.multivalued? = set) Core/param!(set,class!(ar))
                          else ar)),
                    trace(5,"~S -> ~S x ~S\n", r, r.domain,r.range))))


// new: re-compute the numbering but without the side-effects of the interpreter version (v3.067)
Compile/lexical_num(self:any,n:integer) : void
 -> (case self
      (Call lexical_num(self.args, n),
       Instruction let %type:class := self.isa in
          (if (%type % Instruction_with_var.descendents)
                (put(index, self.var, n),
                 n := n + 1,
                 if (n > *variable_index*) *variable_index* := n),
           for s in %type.slots lexical_num(get(s,self), n)),
      bag (for x in self lexical_num(x, n)),
      any nil))


// v3.2 -----------------------------------------------------------------

c_type(self:Defrule) : type -> any
              
// compile a rule definition
c_code(self:Defrule,s:class) : any
 -> let ru := get(self.iClaire/ident), l := list<any>() in
       (//[0] compile a rule ~S // ru,
        for r in Language/relations[ru] 
            (if not(Language/eventMethod?(r)) Tighten(r)),   // ensures better code generation  
        for r in Language/relations[ru]
          (if (open(r) < 2) l :add Call(final, list(r)),
           compile_if_write(r),
           let dn := (r.name /+ "_write"),
               s := string!(dn),
               lb := r.if_write in
             (compile_lambda(s, lb, void), 
              l add Call(put,list(if_write,r,make_function(s))))),
        for r in Language/relations[ru]
          (if Language/eventMethod?(r)
              l :add compileEventMethod(r as property)),
        c_code(Do(l), s))
      
// produce a beautiful if_write demon
compile_if_write(R:relation) : void
 -> let l := demons[R],
        lvar := l[1].formula.vars,  // list(x,y) from 1st demon
        l1 := list<any>(Produce_put(R,lvar[1],lvar[2])),
        l2 := list<any>{ substitution(
                         substitution(
                         substitution( x.formula.body,x.formula.vars[3],lvar[3]),
                         x.formula.vars[1], lvar[1]),
                         x.formula.vars[2], lvar[2]) |  x in l} in
     (put(range,lvar[1],domain(R)),
      put(range,lvar[2],range(R)), 
      for v in lvar put(range,v,class!(v.range)),
      if (l2[1] % If & not(Language/eventMethod?(R)))
         (if ((l2[1] as If).test % And)
             ((l2[1] as If).test := And(args = cdr((l2[1] as If).test.args)))
          else l2[1] := (l2[1] as If).arg),        // first test is useless :)
      if known?(inverse,R)
         (if not(multi?(R)) l1 :add Produce_remove(R.inverse,lvar[3],lvar[1]),
          l1 :add Produce_put(R.inverse,lvar[2],lvar[1])),
       R.if_write := lambda!( list(lvar[1],lvar[2]),
         (if Language/eventMethod?(R) Do(l2)
          else if multi?(R)
             If(test = Call(not,
                            list(Call(%,list(lvar[2],Language/readCall(R,lvar[1]))))),
                arg = Do(l1 /+ l2))
          else Let(var = lvar[3],
                   value = Language/readCall(R,lvar[1]),
                   arg = If(test = Call(!=,list(lvar[2],lvar[3])),
                            arg = Do(l1 /+ l2))))))
               
// create a simple method that will trigger the event
compileEventMethod(p:property) : any
 -> let m:method := p.restrictions[1],
        na := string!(p.name) /+ "_write" in
      add_method!(m,list(p.domain,p.range),void,0,make_function(na))    
 

