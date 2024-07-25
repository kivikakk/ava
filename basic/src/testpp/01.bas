' NEXT FOCUS: fix how we handle remarks so that e.g.
' "IF x THEN 'yz" doesn't parse as if1.
'
' What to do about tabs?

' This file should pretty-print back as itself exactly.
PRINT "Hello","world!"
LET x$ = "Tere"
y$="maailm"
PRINT x$, ", ", y$

IF x$ + x$ = "TereTere" THEN   'umm.

    PRINT "yey"   ' :)
    PRINT 1+2     ' !
END IF

IF 3 >= 2 THEN      PRINT "fine."
IF 3 <= 2 THEN  PRINT "ok"  ELSE PRINT "!!"
IF 3 <= 2 THEN  END  ELSE PRINT "!!"
