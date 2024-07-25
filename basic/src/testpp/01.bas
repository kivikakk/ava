' NEXT FOCUS: fix how we handle remarks so that e.g.
' "IF x THEN 'yz" doesn't parse as if1.

' This file should pretty-print back as itself exactly.
PRINT "Hello", "world!"
LET x$ = "Tere"
y$ = "maailm"
PRINT x$, ", ", y$

' TODO: same-line comments
IF x$ + x$ = "TereTere" THEN

    PRINT "yey"
END IF

IF 3 >= 2 THEN PRINT "fine."
