import numpy as np


def opr_calc(M, s):
    """Compute OPR vector x from Mx=s using the normal equation.

    Solves (M^T M) x = (M^T s). If M^T M is singular, falls back to
    pseudoinverse for a stable least-squares solution.
    """
    matrix_m = np.asarray(M, dtype=float)
    vector_s = np.asarray(s, dtype=float).reshape(-1)

    mtm = matrix_m.T @ matrix_m
    mts = matrix_m.T @ vector_s

    try:
        return np.linalg.solve(mtm, mts)
    except np.linalg.LinAlgError:
        return np.linalg.pinv(mtm) @ mts
