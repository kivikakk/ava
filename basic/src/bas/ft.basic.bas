' PRAGMA PRINTED evaluates \n.

PRINT 1; 2; -3
PRAGMA PRINTED " 1  2 -3 \n"

a% = 1 + 2 * 3
b% = (1 + 2) * 3
PRINT a%, b%
PRAGMA PRINTED " 7             9 \n"

c% = 32767.5
PRINT c%
PRAGMA PRINTED "-32768 \n"

PRINT d%; d&; d!; d#; d$
PRAGMA PRINTED " 0  0  0  0 \n"
