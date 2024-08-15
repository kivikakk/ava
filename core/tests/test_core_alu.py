from .helpers import functional_test


def test_integer_ops():
    functional_test("""
        PRINT 56 + -58
        PRINT -12 * -34
        PRINT -4576 \\ 15
        PRINT -4576 MOD 15
        PRINT -3--5
    """, output=
        b'-2 \n'
        b' 408 \n'
        b'-305 \n'
        b'-1 \n'
        b' 2 \n'
    )
