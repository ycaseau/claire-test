/***********************************************************************/
/**   microCLAIRE                                       Yves Caseau    */
/**   readme.cl                                                        */
/**  Copyright (C) 1998-00 Yves Caseau. All Rights Reserved.           */
/***********************************************************************/

                          claire/.../src/compile
                          ======================



This directory contains the files for two compiler modules:

(1) Optimize
------------



(2) Generate
------------

gsystem.cl contains the toplevel methods that tell how to compile a file or a module.

gexp.cl contains the definition of the "expression" method, which produces an expression
of the target language from a CLAIRE optimized expression x that must satisfy 
c_func(x) = true

gsystem.cl contains the definition of the "statement" method which produces a statement
from the external target language from a CLAIRE optimized instruction.

cgen.cl contains the definition of the C++ code producer, which encapsulate all that is
truly specific to C++.

jgen.cl contains the java code generation file (Bouygues')