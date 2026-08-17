def _solve_linear_system(matrix, vector, tolerance=1e-12):
    """Solve Ax=b with partial-pivot Gaussian elimination."""
    size = len(matrix)
    augmented = [list(map(float, row)) + [float(vector[index])] for index, row in enumerate(matrix)]

    for column in range(size):
        pivot_row = max(range(column, size), key=lambda row: abs(augmented[row][column]))
        if abs(augmented[pivot_row][column]) <= tolerance:
            raise ValueError("The OPR system is rank deficient.")
        if pivot_row != column:
            augmented[column], augmented[pivot_row] = augmented[pivot_row], augmented[column]

        pivot = augmented[column][column]
        for index in range(column, size + 1):
            augmented[column][index] /= pivot

        for row in range(size):
            if row == column:
                continue
            factor = augmented[row][column]
            if abs(factor) <= tolerance:
                continue
            for index in range(column, size + 1):
                augmented[row][index] -= factor * augmented[column][index]

    return [augmented[row][size] for row in range(size)]


def opr_calc(M, s):
    """Compute OPR with normal equations and a small rank-deficiency fallback.

    The implementation intentionally uses only the Python standard library so
    the macOS app can use the newest installed Python 3 without asking users to
    manage third-party packages or another environment.
    """
    rows = [list(map(float, row)) for row in M]
    scores = list(map(float, s))
    if not rows or not rows[0]:
        return []
    if len(rows) != len(scores):
        raise ValueError("The participation matrix and score vector have different lengths.")

    team_count = len(rows[0])
    mtm = [[0.0 for _ in range(team_count)] for _ in range(team_count)]
    mts = [0.0 for _ in range(team_count)]
    for row, score in zip(rows, scores):
        if len(row) != team_count:
            raise ValueError("The participation matrix has inconsistent row lengths.")
        for left in range(team_count):
            mts[left] += row[left] * score
            for right in range(team_count):
                mtm[left][right] += row[left] * row[right]

    try:
        return _solve_linear_system(mtm, mts)
    except ValueError:
        # A tiny ridge term provides a deterministic minimum-norm-like result
        # for events whose alliance schedule does not fully constrain every team.
        scale = max((abs(mtm[index][index]) for index in range(team_count)), default=1.0)
        ridge = max(scale * 1e-10, 1e-10)
        regularized = [row[:] for row in mtm]
        for index in range(team_count):
            regularized[index][index] += ridge
        return _solve_linear_system(regularized, mts)
