import pytest

from .helpers import functional_test


def test_68():
    functional_test("""
        a% = 2
        b% = 34
        c% = a% * b%
        PRINT c%
    """, output=b' 68 \n', stacks=[
        [2],
        [],
        [34],
        [],
        [2],
        [2, 34],
        [2],
        [],
        [68],
        [],
        [68],
        [],
    ])


def test_680():
    functional_test("""
        PRINT (2 * 34) * 10
    """, output=b' 680 \n', stacks=[
        [2],
        [2, 34],
        [2],
        [],
        [68],
        [68, 10],
        [68],
        [],
        [680],
        [],
    ])


@pytest.mark.xfail
def test_print_various():
    functional_test("""
        PRINT 1; 2
        print 2, 3;
        PRINT 3; 4, 5*6*7,
        PRINT "x"
        PRINT "a", "b", "c", "d", "e", "f", "g"
    """, output=
        b' 1  2 \n'
        # v             v             v             v             v             v
        # 12345678901234567890123456789012345678901234567890123456789012345678901234567890
        b' 2             3  3  4       210          x\n'
        b'a             b             c             d             e             f\n'
        b'g\n'
    )
