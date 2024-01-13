'''КОЛ-ВО ПРОХОЖДЕНИЙ'''
completions = 1

defaultPoints = [
    10.0,
    20.0,
    40.0,
    100.0,
    200.0,
    350.0,
    530.0,
    740.0,
    940.0,
    1200.0
]

TIER = 10



WR = 60.0
PR = 60.0

'''ПОБИЛ'''

if PR < WR:
    KOOF = WR/PR
    print(KOOF)
    TIMEPTS = 10.0 + (10.0 * KOOF*1.5) * 1.3
    RESULT = TIMEPTS + completions
    print(RESULT)

else:
    KOOF = WR/PR
    print(KOOF)
    TIMEPTS = 10.0 + (10.0 * KOOF*1.5) / 1.3
    RESULT = TIMEPTS + completions*0.75
    print(RESULT)